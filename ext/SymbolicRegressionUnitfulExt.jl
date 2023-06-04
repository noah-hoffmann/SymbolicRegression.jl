module SymbolicRegressionUnitfulExt

if isdefined(Base, :get_extension)
    import Unitful: Units, uparse, dimension, ustrip, Quantity, DimensionError
    import Unitful: @u_str, @dimension, NoDims, unit
    using SymbolicRegression: Node, Options, tree_mapreduce
    import SymbolicRegression.CoreModule.DatasetModule: get_units
    import SymbolicRegression.CheckConstraintsModule: violates_dimensional_constraints
else
    import ..Unitful: Units, uparse, dimension, ustrip, Quantity, DimensionError
    import ..Unitful: @u_str, @dimension, NoDims, unit
    using ..SymbolicRegression: Node, Options, tree_mapreduce
    import ..SymbolicRegression.CoreModule.DatasetModule: get_units
    import ..SymbolicRegression.CheckConstraintsModule: violates_dimensional_constraints
end

const Warned = Ref(false)
const WarnedLock = Threads.SpinLock()

function display_warning(e, op)
    Warned.x && return nothing
    @warn "Encountered $(e) when calling $(op).\n" *
        "It is likely you have defined a custom operator with too generic a type signature.\n" *
        "I will try to use `try-catch` for dimensional analysis, but this will be significantly slower.\n" *
        "To avoid this warning, please define your operator on specific types, such as `AbstractFloat`.\n" *
        "If you want units to be propagated through your operator, you can look at how `Base.:+` is " *
        "defined on `WildcardDimensionWrapper` in SymbolicRegressionUnitfulExt.jl."
    Warned.x = true
    return nothing
end

# https://discourse.julialang.org/t/performance-of-hasmethod-vs-try-catch-on-methoderror/99827/12
# Faster way to catch method errors:
function _safe_call end
@inline function safe_call(f::F, x::T, default_return::T=one(T)) where {F,T}
    hasmethod(_safe_call, Tuple{F,T}) && return _safe_call(f, x)::Tuple{T,Bool}
    output = try
        (f(x), true)
    catch e
        !isa(e, MethodError) && rethrow(e)
        (default_return, false)
    end
    if output[2]
        @eval _safe_call(f::$F, x::$T) = (f(x), true)
    else
        @eval _safe_call(::$F, ::$T) = ($default_return, false)
    end
    return output
end

macro catch_method_error(op, ex)
    quote
        try
            $(esc(ex))
        catch e
            !isa(e, Union{MethodError,DimensionError}) && rethrow(e)
            !Warned.x && lock(WarnedLock) do
                display_warning(e, $(esc(op)))
                return nothing
            end
            return false
        end
    end
end

"""
    WildcardDimensionWrapper{T}

A wrapper for `Quantity{T}` that allows for a wildcard feature, indicating
there is a free constant whose dimensions are not yet determined.
Also stores a flag indicating whether an expression is dimensionally consistent.
"""
struct WildcardDimensionWrapper{T}
    val::Quantity{T}
    wildcard::Bool
    violates::Bool
end
Base.isfinite(x::WildcardDimensionWrapper) = isfinite(x.val)
same_dimensions(x::Quantity, y::Quantity) = dimension(x) == dimension(y)
has_no_dims(x::Quantity) = dimension(x) == NoDims

# Overload *, /, +, -, ^ for WildcardDimensionWrapper, as
# we want wildcards to propagate through these operations.
for op in (:(Base.:*), :(Base.:/))
    @eval function $(op)(
        l::WildcardDimensionWrapper{T}, r::WildcardDimensionWrapper{T}
    ) where {T}
        l.violates && return l
        return WildcardDimensionWrapper{T}(
            $(op)(l.val, r.val), l.wildcard || r.wildcard, false
        )
    end
end
for op in (:(Base.:+), :(Base.:-))
    @eval function $(op)(
        l::WildcardDimensionWrapper{T}, r::WildcardDimensionWrapper{T}
    ) where {T}
        (l.violates || r.violates) && return l
        if same_dimensions(l.val, r.val)
            return WildcardDimensionWrapper{T}(
                $(op)(l.val, r.val), l.wildcard && r.wildcard, false
            )
        elseif l.wildcard && r.wildcard
            return WildcardDimensionWrapper{T}(
                $(op)(ustrip(l.val), ustrip(r.val)), l.wildcard && r.wildcard, false
            )
        elseif l.wildcard
            return WildcardDimensionWrapper{T}(
                $(op)(ustrip(l.val) * unit(r.val), r.val), false, false
            )
        elseif r.wildcard
            return WildcardDimensionWrapper{T}(
                $(op)(l.val, ustrip(r.val) * unit(l.val)), false, false
            )
        else
            return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)
        end
    end
end
function Base.:^(l::WildcardDimensionWrapper{T}, r::WildcardDimensionWrapper{T}) where {T}
    (l.violates || r.violates) && return l
    # TODO: Does this need to check for other violations? (See `safe_pow`)
    if has_no_dims(r.val)
        return WildcardDimensionWrapper{T}(l.val^r.val, l.wildcard, false)
    elseif r.wildcard
        return WildcardDimensionWrapper{T}(l.val^ustrip(r.val), l.wildcard, false)
    else
        return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)
    end
end

# Define dimensionally-aware evaluation routine:
@inline function deg0_eval(x::AbstractVector{T}, variable_units, t::Node{T}) where {T}
    if t.constant
        return WildcardDimensionWrapper{T}(t.val::T, true, false)
    else
        return WildcardDimensionWrapper{T}(
            x[t.feature] * variable_units[t.feature], false, false
        )
    end
end
function deg1_eval(op::F, l::WildcardDimensionWrapper{T}) where {F,T}
    l.violates && return l
    !isfinite(l) && return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)

    hasmethod(op, Tuple{WildcardDimensionWrapper{T}}) &&
        @catch_method_error op return op(l)::WildcardDimensionWrapper{T}
    l.wildcard && return WildcardDimensionWrapper{T}(op(ustrip(l.val))::T, false, false)
    return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)
end
function deg2_eval(
    op::F, l::WildcardDimensionWrapper{T}, r::WildcardDimensionWrapper{T}
) where {F,T}
    l.violates && return l
    r.violates && return r
    (!isfinite(l) || !isfinite(r)) &&
        return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)

    hasmethod(op, Tuple{WildcardDimensionWrapper{T},WildcardDimensionWrapper{T}}) &&
        @catch_method_error op return op(l, r)::WildcardDimensionWrapper{T}
    l.wildcard &&
        hasmethod(op, Tuple{T,WildcardDimensionWrapper{T}}) &&
        @catch_method_error op return op(ustrip(l.val), r)::WildcardDimensionWrapper{T}
    r.wildcard &&
        hasmethod(op, Tuple{WildcardDimensionWrapper{T},T}) &&
        @catch_method_error op return op(l, ustrip(r.val))::WildcardDimensionWrapper{T}
    l.wildcard &&
        r.wildcard &&
        return WildcardDimensionWrapper{T}(
            op(ustrip(l.val), ustrip(r.val))::T, false, false
        )
    return WildcardDimensionWrapper{T}(one(Quantity{T}), false, true)
end

@inline degn_eval(operators, t, l) = deg1_eval(operators.unaops[t.op], l)
@inline degn_eval(operators, t, l, r) = deg2_eval(operators.binops[t.op], l, r)

function violates_dimensional_constraints(
    tree::Node{T},
    variable_units::Union{AbstractVector,Tuple{Any,Vararg{Any}}},
    x::AbstractVector{T},
    options::Options,
) where {T}
    operators = options.operators
    # We propagate (quantity, has_constant). If `has_constant`,
    # we are free to change the type.
    dimensional_result = tree_mapreduce(
        t -> deg0_eval(x, variable_units, t),
        identity,
        (t, args...) -> degn_eval(operators, t, args...),
        tree,
        WildcardDimensionWrapper{T},
    )::WildcardDimensionWrapper{T}
    # TODO: Should also check against output type.
    return dimensional_result.violates
end

function get_units(x::AbstractArray)
    return Tuple(
        map(x) do xi
            if isa(xi, AbstractString)
                return uparse(xi)
            else
                return xi
            end
        end,
    )
end

end
