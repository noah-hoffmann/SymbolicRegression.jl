module SymbolicRegression

# Types
export Population,
    PopMember,
    HallOfFame,
    Options,
    Dataset,
    AbstractDataset,
    MutationWeights,
    Node,
    SRRegressor,
    MultitargetSRRegressor,
    LOSS_TYPE,
    DATA_TYPE,

    #Functions:
    equation_search,
    s_r_cycle,
    calculate_pareto_frontier,
    count_nodes,
    compute_complexity,
    print_tree,
    string_tree,
    eval_tree_array,
    eval_diff_tree_array,
    eval_grad_tree_array,
    differentiable_eval_tree_array,
    set_node!,
    copy_node,
    node_to_symbolic,
    symbolic_to_node,
    simplify_tree,
    tree_mapreduce,
    combine_operators,
    gen_random_tree,
    gen_random_tree_fixed_size,
    @extend_operators,

    #Operators
    plus,
    sub,
    mult,
    square,
    cube,
    pow,
    safe_pow,
    div,
    safe_log,
    safe_log2,
    safe_log10,
    safe_log1p,
    safe_acosh,
    safe_sqrt,
    neg,
    greater,
    relu,
    logical_or,
    logical_and,

    # special operators
    gamma,
    erf,
    erfc,
    atanh_clip

using Distributed
import Printf: @printf, @sprintf
import PackageExtensionCompat: @require_extensions
using Pkg: Pkg
import TOML: parsefile
import Random: seed!, shuffle!
using Reexport
import DynamicExpressions:
    Node,
    copy_node,
    set_node!,
    string_tree,
    print_tree,
    count_nodes,
    get_constants,
    set_constants,
    index_constants,
    NodeIndex,
    eval_tree_array,
    differentiable_eval_tree_array,
    eval_diff_tree_array,
    eval_grad_tree_array,
    node_to_symbolic,
    symbolic_to_node,
    combine_operators,
    simplify_tree,
    tree_mapreduce,
    set_default_variable_names!
@reexport import LossFunctions:
    MarginLoss,
    DistanceLoss,
    SupervisedLoss,
    ZeroOneLoss,
    LogitMarginLoss,
    PerceptronLoss,
    HingeLoss,
    L1HingeLoss,
    L2HingeLoss,
    SmoothedL1HingeLoss,
    ModifiedHuberLoss,
    L2MarginLoss,
    ExpLoss,
    SigmoidLoss,
    DWDMarginLoss,
    LPDistLoss,
    L1DistLoss,
    L2DistLoss,
    PeriodicLoss,
    HuberLoss,
    EpsilonInsLoss,
    L1EpsilonInsLoss,
    L2EpsilonInsLoss,
    LogitDistLoss,
    QuantileLoss,
    LogCoshLoss

# https://discourse.julialang.org/t/how-to-find-out-the-version-of-a-package-from-its-module/37755/15
const PACKAGE_VERSION = try
    let project = parsefile(joinpath(pkgdir(@__MODULE__), "Project.toml"))
        VersionNumber(project["version"])
    end
catch
    VersionNumber(0, 0, 0)
end

function deprecate_varmap(variable_names, varMap, func_name)
    if varMap !== nothing
        Base.depwarn("`varMap` is deprecated; use `variable_names` instead", func_name)
        @assert variable_names === nothing "Cannot pass both `varMap` and `variable_names`"
        variable_names = varMap
    end
    return variable_names
end

include("Utils.jl")
include("InterfaceDynamicQuantities.jl")
include("Core.jl")
include("InterfaceDynamicExpressions.jl")
include("Recorder.jl")
include("Complexity.jl")
include("DimensionalAnalysis.jl")
include("CheckConstraints.jl")
include("AdaptiveParsimony.jl")
include("MutationFunctions.jl")
include("LossFunctions.jl")
include("PopMember.jl")
include("ConstantOptimization.jl")
include("Population.jl")
include("HallOfFame.jl")
include("Mutate.jl")
include("RegularizedEvolution.jl")
include("SingleIteration.jl")
include("ProgressBars.jl")
include("Migration.jl")
include("SearchUtils.jl")

import .CoreModule:
    MAX_DEGREE,
    BATCH_DIM,
    FEATURE_DIM,
    DATA_TYPE,
    LOSS_TYPE,
    RecordType,
    Dataset,
    AbstractDataset,
    Options,
    MutationWeights,
    plus,
    sub,
    mult,
    square,
    cube,
    pow,
    safe_pow,
    div,
    safe_log,
    safe_log2,
    safe_log10,
    safe_log1p,
    safe_sqrt,
    safe_acosh,
    neg,
    greater,
    greater,
    relu,
    logical_or,
    logical_and,
    gamma,
    erf,
    erfc,
    atanh_clip
import .UtilsModule:
    debug, debug_inline, is_anonymous_function, recursive_merge, json3_write
import .ComplexityModule: compute_complexity
import .CheckConstraintsModule: check_constraints
import .AdaptiveParsimonyModule:
    RunningSearchStatistics, update_frequencies!, move_window!, normalize_frequencies!
import .MutationFunctionsModule:
    gen_random_tree,
    gen_random_tree_fixed_size,
    random_node,
    random_node_and_parent,
    crossover_trees
import .InterfaceDynamicExpressionsModule: @extend_operators
import .LossFunctionsModule: eval_loss, score_func, update_baseline_loss!
import .PopMemberModule: PopMember, copy_pop_member, copy_pop_member_reset_birth
import .PopulationModule:
    Population, copy_population, best_sub_pop, record_population, best_of_sample
import .HallOfFameModule:
    HallOfFame, calculate_pareto_frontier, string_dominating_pareto_curve
import .SingleIterationModule: s_r_cycle, optimize_and_simplify_population
import .ProgressBarsModule: WrappedProgressBar
import .RecorderModule: @recorder, find_iteration_from_record
import .MigrationModule: migrate!
import .SearchUtilsModule:
    next_worker,
    @sr_spawner,
    watch_stream,
    close_reader!,
    check_for_user_quit,
    check_for_loss_threshold,
    check_for_timeout,
    check_max_evals,
    ResourceMonitor,
    start_work_monitor!,
    stop_work_monitor!,
    estimate_work_fraction,
    update_progress_bar!,
    print_search_state,
    init_dummy_pops,
    load_saved_hall_of_fame,
    load_saved_population,
    construct_datasets

include("deprecates.jl")
include("Configure.jl")

"""
    equation_search(X, y[; kws...])

Perform a distributed equation search for functions `f_i` which
describe the mapping `f_i(X[:, j]) ≈ y[i, j]`. Options are
configured using SymbolicRegression.Options(...),
which should be passed as a keyword argument to options.
One can turn off parallelism with `numprocs=0`,
which is useful for debugging and profiling.

# Arguments
- `X::AbstractMatrix{T}`:  The input dataset to predict `y` from.
    The first dimension is features, the second dimension is rows.
- `y::Union{AbstractMatrix{T}, AbstractVector{T}}`: The values to predict. The first dimension
    is the output feature to predict with each equation, and the
    second dimension is rows.
- `niterations::Int=10`: The number of iterations to perform the search.
    More iterations will improve the results.
- `weights::Union{AbstractMatrix{T}, AbstractVector{T}, Nothing}=nothing`: Optionally
    weight the loss for each `y` by this value (same shape as `y`).
- `options::Options=Options()`: The options for the search, such as
    which operators to use, evolution hyperparameters, etc.
- `variable_names::Union{Vector{String}, Nothing}=nothing`: The names
    of each feature in `X`, which will be used during printing of equations.
- `display_variable_names::Union{Vector{String}, Nothing}=variable_names`: Names
    to use when printing expressions during the search, but not when saving
    to an equation file.
- `y_variable_names::Union{String,AbstractVector{String},Nothing}=nothing`: The
    names of each output feature in `y`, which will be used during printing
    of equations.
- `parallelism=:multithreading`: What parallelism mode to use.
    The options are `:multithreading`, `:multiprocessing`, and `:serial`.
    By default, multithreading will be used. Multithreading uses less memory,
    but multiprocessing can handle multi-node compute. If using `:multithreading`
    mode, the number of threads available to julia are used. If using
    `:multiprocessing`, `numprocs` processes will be created dynamically if
    `procs` is unset. If you have already allocated processes, pass them
    to the `procs` argument and they will be used.
    You may also pass a string instead of a symbol, like `"multithreading"`.
- `numprocs::Union{Int, Nothing}=nothing`:  The number of processes to use,
    if you want `equation_search` to set this up automatically. By default
    this will be `4`, but can be any number (you should pick a number <=
    the number of cores available).
- `procs::Union{Vector{Int}, Nothing}=nothing`: If you have set up
    a distributed run manually with `procs = addprocs()` and `@everywhere`,
    pass the `procs` to this keyword argument.
- `addprocs_function::Union{Function, Nothing}=nothing`: If using multiprocessing
    (`parallelism=:multithreading`), and are not passing `procs` manually,
    then they will be allocated dynamically using `addprocs`. However,
    you may also pass a custom function to use instead of `addprocs`.
    This function should take a single positional argument,
    which is the number of processes to use, as well as the `lazy` keyword argument.
    For example, if set up on a slurm cluster, you could pass
    `addprocs_function = addprocs_slurm`, which will set up slurm processes.
- `runtests::Bool=true`: Whether to run (quick) tests before starting the
    search, to see if there will be any problems during the equation search
    related to the host environment.
- `saved_state=nothing`: If you have already
    run `equation_search` and want to resume it, pass the state here.
    To get this to work, you need to have set return_state=true,
    which will cause `equation_search` to return the state. The second
    element of the state is the regular return value with the hall of fame.
    Note that you cannot change the operators or dataset, but most other options
    should be changeable.
- `return_state::Union{Bool, Nothing}=nothing`: Whether to return the
    state of the search for warm starts. By default this is false.
- `loss_type::Type=Nothing`: If you would like to use a different type
    for the loss than for the data you passed, specify the type here.
    Note that if you pass complex data `::Complex{L}`, then the loss
    type will automatically be set to `L`.
- `verbosity`: Whether to print debugging statements or not.
- `progress`: Whether to use a progress bar output. Only available for
    single target output.
- `X_units::Union{AbstractVector,Nothing}=nothing`: The units of the dataset,
    to be used for dimensional constraints. For example, if `X_units=["kg", "m"]`,
    then the first feature will have units of kilograms, and the second will
    have units of meters.
- `y_units=nothing`: The units of the output, to be used for dimensional constraints.
    If `y` is a matrix, then this can be a vector of units, in which case
    each element corresponds to each output feature.

# Returns
- `hallOfFame::HallOfFame`: The best equations seen during the search.
    hallOfFame.members gives an array of `PopMember` objects, which
    have their tree (equation) stored in `.tree`. Their score (loss)
    is given in `.score`. The array of `PopMember` objects
    is enumerated by size from `1` to `options.maxsize`.
"""
function equation_search(
    X::AbstractMatrix{T},
    y::AbstractMatrix{T};
    niterations::Int=10,
    weights::Union{AbstractMatrix{T},AbstractVector{T},Nothing}=nothing,
    options::Options=Options(),
    variable_names::Union{AbstractVector{String},Nothing}=nothing,
    display_variable_names::Union{AbstractVector{String},Nothing}=variable_names,
    y_variable_names::Union{String,AbstractVector{String},Nothing}=nothing,
    parallelism=:multithreading,
    numprocs::Union{Int,Nothing}=nothing,
    procs::Union{Vector{Int},Nothing}=nothing,
    addprocs_function::Union{Function,Nothing}=nothing,
    runtests::Bool=true,
    saved_state=nothing,
    return_state::Union{Bool,Nothing}=nothing,
    loss_type::Type{Linit}=Nothing,
    verbosity::Union{Integer,Nothing}=nothing,
    progress::Union{Bool,Nothing}=nothing,
    X_units::Union{AbstractVector,Nothing}=nothing,
    y_units=nothing,
    v_dim_out::Val{dim_out}=Val(nothing),
    # Deprecated:
    multithreaded=nothing,
    varMap=nothing,
) where {T<:DATA_TYPE,Linit,dim_out}
    if multithreaded !== nothing
        error(
            "`multithreaded` is deprecated. Use the `parallelism` argument instead. " *
            "Choose one of :multithreaded, :multiprocessing, or :serial.",
        )
    end
    variable_names = deprecate_varmap(variable_names, varMap, :equation_search)

    if weights !== nothing
        @assert length(weights) == length(y)
        weights = reshape(weights, size(y))
    end
    if T <: Complex && loss_type == Nothing
        get_base_type(::Type{Complex{BT}}) where {BT} = BT
        loss_type = get_base_type(T)
    end

    datasets = construct_datasets(
        X,
        y,
        weights,
        variable_names,
        display_variable_names,
        y_variable_names,
        X_units,
        y_units,
        loss_type,
    )

    return equation_search(
        datasets;
        niterations=niterations,
        options=options,
        parallelism=parallelism,
        numprocs=numprocs,
        procs=procs,
        addprocs_function=addprocs_function,
        runtests=runtests,
        saved_state=saved_state,
        return_state=return_state,
        verbosity=verbosity,
        progress=progress,
        v_dim_out=Val(dim_out),
    )
end

function equation_search(
    X::AbstractMatrix{T1}, y::AbstractMatrix{T2}; kw...
) where {T1<:DATA_TYPE,T2<:DATA_TYPE}
    U = promote_type(T1, T2)
    return equation_search(
        convert(AbstractMatrix{U}, X), convert(AbstractMatrix{U}, y); kw...
    )
end

function equation_search(
    X::AbstractMatrix{T1}, y::AbstractVector{T2}; kw...
) where {T1<:DATA_TYPE,T2<:DATA_TYPE}
    return equation_search(X, reshape(y, (1, size(y, 1))); kw..., v_dim_out=Val(1))
end

function equation_search(dataset::Dataset; kws...)
    return equation_search([dataset]; kws..., v_dim_out=Val(1))
end

function equation_search(
    datasets::Vector{D};
    niterations::Int=10,
    options::Options=Options(),
    parallelism=:multithreading,
    numprocs::Union{Int,Nothing}=nothing,
    procs::Union{Vector{Int},Nothing}=nothing,
    addprocs_function::Union{Function,Nothing}=nothing,
    runtests::Bool=true,
    saved_state=nothing,
    return_state::Union{Bool,Nothing}=nothing,
    verbosity::Union{Int,Nothing}=nothing,
    progress::Union{Bool,Nothing}=nothing,
    v_dim_out::Val{dim_out}=Val(nothing),
) where {dim_out,T<:DATA_TYPE,L<:LOSS_TYPE,D<:AbstractDataset{T,L}}
    v_concurrency, concurrency = if parallelism in (:multithreading, "multithreading")
        (Val(:multithreading), :multithreading)
    elseif parallelism in (:multiprocessing, "multiprocessing")
        (Val(:multiprocessing), :multiprocessing)
    elseif parallelism in (:serial, "serial")
        (Val(:serial), :serial)
    else
        error(
            "Invalid parallelism mode: $parallelism. " *
            "You must choose one of :multithreading, :multiprocessing, or :serial.",
        )
    end
    not_distributed = concurrency in (:multithreading, :serial)
    not_distributed &&
        procs !== nothing &&
        error(
            "`procs` should not be set when using `parallelism=$(parallelism)`. Please use `:multiprocessing`.",
        )
    not_distributed &&
        numprocs !== nothing &&
        error(
            "`numprocs` should not be set when using `parallelism=$(parallelism)`. Please use `:multiprocessing`.",
        )

    # TODO: Still not type stable. Should be able to pass `Val{return_state}`.
    should_return_state = if options.return_state === nothing
        return_state === nothing ? false : return_state
    else
        @assert(
            return_state === nothing,
            "You cannot set `return_state` in both the `Options` and in the passed arguments."
        )
        options.return_state
    end

    _v_dim_out = if dim_out === nothing
        length(datasets) > 1 ? Val(2) : Val(1)
    else
        Val(dim_out)
    end

    verbosity = if verbosity === nothing && options.verbosity === nothing
        1
    elseif verbosity === nothing
        options.verbosity
    elseif options.verbosity === nothing
        verbosity
    else
        error(
            "You cannot set `verbosity` in both the search parameters `Options` and the call to `equation_search`.",
        )
    end
    progress = if progress === nothing && options.progress === nothing
        (verbosity > 0) && length(datasets) == 1
    elseif progress === nothing
        options.progress
    elseif options.progress === nothing
        progress
    else
        error(
            "You cannot set `progress` in both the search parameters `Options` and the call to `equation_search`.",
        )
    end
    if progress
        @assert(
            length(datasets) == 1,
            "You cannot display a progress bar for multi-output searches."
        )
        @assert(verbosity > 0, "You cannot display a progress bar with `verbosity=0`.")
    end

    return _equation_search(
        v_concurrency,
        _v_dim_out,
        datasets,
        niterations,
        options,
        numprocs,
        procs,
        addprocs_function,
        runtests,
        saved_state,
        verbosity,
        progress,
        Val(should_return_state),
    )
end

function _equation_search(
    ::Val{parallelism},
    ::Val{dim_out},
    datasets::Vector{D},
    niterations::Int,
    options::Options,
    numprocs::Union{Int,Nothing},
    procs::Union{Vector{Int},Nothing},
    addprocs_function::Union{Function,Nothing},
    runtests::Bool,
    saved_state,
    verbosity,
    progress,
    ::Val{should_return_state},
) where {T<:DATA_TYPE,L<:LOSS_TYPE,D<:AbstractDataset{T,L},parallelism,should_return_state,dim_out}
    if options.deterministic
        if parallelism != :serial
            error("Determinism is only guaranteed for serial mode.")
        end
    end
    if parallelism == :multithreading
        if Threads.nthreads() == 1
            @warn "You are using multithreading mode, but only one thread is available. Try starting julia with `--threads=auto`."
        end
    end
    if any(d -> d.X_units !== nothing || d.y_units !== nothing, datasets)
        if options.dimensional_constraint_penalty === nothing && saved_state === nothing
            @warn "You are using dimensional constraints, but `dimensional_constraint_penalty` was not set. The default penalty of `1000.0` will be used."
        end
    end

    stdin_reader = watch_stream(stdin)

    if options.define_helper_functions
        set_default_variable_names!(first(datasets).variable_names)
    end

    example_dataset = datasets[1]
    nout = size(datasets, 1)
    @assert (nout == 1 || dim_out == 2)

    if runtests
        test_option_configuration(T, options)
        # Testing the first output variable is the same:
        if typeof(example_dataset) <: Dataset
            test_dataset_configuration(example_dataset, options, verbosity)
        else
            debug(
                (verbosity > 0 || options.progress),
                "Note: you are running with a custom Dataset type. No testing of the dataset configuration is performed make sure your data is correct and that you use a compatible loss function.",
            )
        end
    end

    for dataset in datasets
        update_baseline_loss!(dataset, options)
    end

    if options.seed !== nothing
        seed!(options.seed)
    end
    # Start a population on every process
    #    Store the population, hall of fame
    allPopsType = if parallelism == :serial
        Tuple{Population,HallOfFame,RecordType,Float64}
    elseif parallelism == :multiprocessing
        Future
    else
        Task
    end

    allPops = [allPopsType[] for j in 1:nout]
    init_pops = [allPopsType[] for j in 1:nout]
    tasks = [Task[] for j in 1:nout]
    # Set up a channel to send finished populations back to head node
    channels = if parallelism == :multiprocessing
        [[RemoteChannel(1) for i in 1:(options.populations)] for j in 1:nout]
    else
        [[Channel(1) for i in 1:(options.populations)] for j in 1:nout]
        # (Unused for :serial)
    end

    # This is a recorder for populations, but is not actually used for processing, just
    # for the final return.
    returnPops = init_dummy_pops(options.populations, datasets, options)
    # These initial populations are discarded:
    bestSubPops = init_dummy_pops(options.populations, datasets, options)

    actualMaxsize = options.maxsize + MAX_DEGREE

    # TODO: Should really be one per population too.
    all_running_search_statistics = [
        RunningSearchStatistics(; options=options) for j in 1:nout
    ]

    record = RecordType("options" => "$(options)")

    curmaxsizes = if iszero(options.warmup_maxsize_by)
        fill(options.maxsize, nout)
    else
        fill(convert(typeof(options.maxsize), 3), nout)
    end

    # Records the number of evaluations:
    # Real numbers indicate use of batching.
    num_evals = [[0.0 for i in 1:(options.populations)] for j in 1:nout]

    we_created_procs = false
    ##########################################################################
    ### Distributed code:
    ##########################################################################
    if parallelism == :multiprocessing
        if addprocs_function === nothing
            addprocs_function = addprocs
        end
        if numprocs === nothing && procs === nothing
            numprocs = 4
            procs = addprocs_function(numprocs; lazy=false)
            we_created_procs = true
        elseif numprocs === nothing
            numprocs = length(procs)
        elseif procs === nothing
            procs = addprocs_function(numprocs; lazy=false)
            we_created_procs = true
        end

        if we_created_procs
            project_path = splitdir(Pkg.project().path)[1]
            activate_env_on_workers(procs, project_path, options, verbosity)
            import_module_on_workers(procs, @__FILE__, options, verbosity)
        end
        move_functions_to_workers(procs, options, example_dataset, verbosity)
        if runtests
            test_module_on_workers(procs, options, verbosity)
        end

        if runtests
            test_entire_pipeline(procs, example_dataset, options, verbosity)
        end
    end
    # Get the next worker process to give a job:
    worker_assignment = Dict{Tuple{Int,Int},Int}()

    hallOfFame = load_saved_hall_of_fame(saved_state)
    hallOfFame = if hallOfFame === nothing
        [HallOfFame(options, T, L) for j in 1:nout]
    else
        # Recompute losses for the hall of fame, in
        # case the dataset changed:
        for (hof, dataset) in zip(hallOfFame, datasets)
            for member in hof.members[hof.exists]
                score, result_loss = score_func(dataset, member, options)
                member.score = score
                member.loss = result_loss
            end
        end
        hallOfFame
    end
    @assert length(hallOfFame) == nout
    hallOfFame::Vector{HallOfFame{T,L}}

    for j in 1:nout, i in 1:(options.populations)
        worker_idx = next_worker(worker_assignment, procs)
        if parallelism == :multiprocessing
            worker_assignment[(j, i)] = worker_idx
        end

        saved_pop = load_saved_population(saved_state; out=j, pop=i)

        if saved_pop !== nothing && length(saved_pop.members) == options.population_size
            saved_pop::Population{T,L}
            ## Update losses:
            for member in saved_pop.members
                score, result_loss = score_func(datasets[j], member, options)
                member.score = score
                member.loss = result_loss
            end
            copy_pop = copy_population(saved_pop)
            new_pop = @sr_spawner parallelism worker_idx (
                copy_pop, HallOfFame(options, T, L), RecordType(), 0.0
            )
        else
            if saved_pop !== nothing
                @warn "Recreating population (output=$(j), population=$(i)), as the saved one doesn't have the correct number of members."
            end
            new_pop = @sr_spawner parallelism worker_idx (
                Population(
                    datasets[j];
                    population_size=options.population_size,
                    nlength=3,
                    options=options,
                    nfeatures=datasets[j].nfeatures,
                ),
                HallOfFame(options, T, L),
                RecordType(),
                Float64(options.population_size),
            )
            # This involves population_size evaluations, on the full dataset:
        end
        push!(init_pops[j], new_pop)
    end
    # 2. Start the cycle on every process:
    for j in 1:nout, i in 1:(options.populations)
        dataset = datasets[j]
        running_search_statistics = all_running_search_statistics[j]
        curmaxsize = curmaxsizes[j]
        @recorder record["out$(j)_pop$(i)"] = RecordType()
        worker_idx = next_worker(worker_assignment, procs)
        if parallelism == :multiprocessing
            worker_assignment[(j, i)] = worker_idx
        end

        # TODO - why is this needed??
        # Multi-threaded doesn't like to fetch within a new task:
        c_rss = deepcopy(running_search_statistics)
        updated_pop = @sr_spawner parallelism worker_idx let
            in_pop = if parallelism in (:multiprocessing, :multithreading)
                fetch(init_pops[j][i])[1]
            else
                init_pops[j][i][1]
            end

            cur_record = RecordType()
            @recorder cur_record["out$(j)_pop$(i)"] = RecordType(
                "iteration0" => record_population(in_pop, options)
            )
            tmp_num_evals = 0.0
            normalize_frequencies!(c_rss)
            tmp_pop, tmp_best_seen, evals_from_cycle = s_r_cycle(
                dataset,
                in_pop,
                options.ncycles_per_iteration,
                curmaxsize,
                c_rss;
                verbosity=verbosity,
                options=options,
                record=cur_record,
            )
            tmp_num_evals += evals_from_cycle
            tmp_pop, evals_from_optimize = optimize_and_simplify_population(
                dataset, tmp_pop, options, curmaxsize, cur_record
            )
            tmp_num_evals += evals_from_optimize
            if options.batching
                for i_member in 1:(options.maxsize + MAX_DEGREE)
                    score, result_loss = score_func(
                        dataset, tmp_best_seen.members[i_member], options
                    )
                    tmp_best_seen.members[i_member].score = score
                    tmp_best_seen.members[i_member].loss = result_loss
                    tmp_num_evals += 1
                end
            end
            (tmp_pop, tmp_best_seen, cur_record, tmp_num_evals)
        end
        push!(allPops[j], updated_pop)
    end

    debug(verbosity > 0, "Started!")
    start_time = time()
    total_cycles = options.populations * niterations
    cycles_remaining = [total_cycles for j in 1:nout]
    if progress
        #TODO: need to iterate this on the max cycles remaining!
        sum_cycle_remaining = sum(cycles_remaining)
        progress_bar = WrappedProgressBar(
            1:sum_cycle_remaining; width=options.terminal_width
        )
    end

    last_print_time = time()
    last_speed_recording_time = time()
    num_evals_last = sum(sum, num_evals)
    num_evals_since_last = sum(sum, num_evals) - num_evals_last
    print_every_n_seconds = 5
    equation_speed = Float32[]

    if parallelism in (:multiprocessing, :multithreading)
        for j in 1:nout, i in 1:(options.populations)
            # Start listening for each population to finish:
            t = @async put!(channels[j][i], fetch(allPops[j][i]))
            push!(tasks[j], t)
        end
    end

    # Randomly order which order to check populations:
    # This is done so that we do work on all nout equally.
    all_idx = [(j, i) for j in 1:nout for i in 1:(options.populations)]
    shuffle!(all_idx)
    kappa = 0
    resource_monitor = ResourceMonitor(;
        absolute_start_time=time(),
        # Storing n times as many monitoring intervals as populations seems like it will
        # help get accurate resource estimates:
        num_intervals_to_store=options.populations * 100 * nout,
    )
    while sum(cycles_remaining) > 0
        kappa += 1
        if kappa > options.populations * nout
            kappa = 1
        end
        # nout, populations:
        j, i = all_idx[kappa]

        # Check if error on population:
        if parallelism in (:multiprocessing, :multithreading)
            if istaskfailed(tasks[j][i])
                fetch(tasks[j][i])
                error("Task failed for population")
            end
        end
        # Non-blocking check if a population is ready:
        population_ready = if parallelism in (:multiprocessing, :multithreading)
            # TODO: Implement type assertions based on parallelism.
            isready(channels[j][i])
        else
            true
        end
        # Don't start more if this output has finished its cycles:
        # TODO - this might skip extra cycles?
        population_ready &= (cycles_remaining[j] > 0)
        if population_ready
            start_work_monitor!(resource_monitor)
            # Take the fetch operation from the channel since its ready
            (cur_pop, best_seen, cur_record, cur_num_evals) =
                if parallelism in (:multiprocessing, :multithreading)
                    take!(channels[j][i])
                else
                    allPops[j][i]
                end
            cur_pop::Population
            best_seen::HallOfFame
            cur_record::RecordType
            cur_num_evals::Float64
            returnPops[j][i] = copy_population(cur_pop)
            bestSubPops[j][i] = best_sub_pop(cur_pop; topn=options.topn)
            @recorder record = recursive_merge(record, cur_record)
            num_evals[j][i] += cur_num_evals

            dataset = datasets[j]
            curmaxsize = curmaxsizes[j]

            #Try normal copy...
            bestPops = Population([
                member for pop in bestSubPops[j] for member in pop.members
            ])

            ###################################################################
            # Hall Of Fame updating ###########################################
            for (i_member, member) in enumerate(
                Iterators.flatten((cur_pop.members, best_seen.members[best_seen.exists]))
            )
                part_of_cur_pop = i_member <= length(cur_pop.members)
                size = compute_complexity(member, options)

                if part_of_cur_pop
                    update_frequencies!(all_running_search_statistics[j]; size=size)
                end
                actualMaxsize = options.maxsize + MAX_DEGREE

                valid_size = 0 < size < actualMaxsize
                if valid_size
                    already_filled = hallOfFame[j].exists[size]
                    better_than_current = member.score < hallOfFame[j].members[size].score
                    if !already_filled || better_than_current
                        hallOfFame[j].members[size] = copy_pop_member(member)
                        hallOfFame[j].exists[size] = true
                    end
                end
            end
            ###################################################################

            # Dominating pareto curve - must be better than all simpler equations
            dominating = calculate_pareto_frontier(hallOfFame[j])

            if options.save_to_file
                output_file = options.output_file
                if nout > 1
                    output_file = output_file * ".out$j"
                end
                # Write file twice in case exit in middle of filewrite
                for out_file in (output_file, output_file * ".bkup")
                    open(out_file, "w") do io
                        println(io, "Complexity,Loss,Equation")
                        for member in dominating
                            println(
                                io,
                                "$(compute_complexity(member, options)),$(member.loss),\"" *
                                "$(string_tree(member.tree, options, variable_names=dataset.variable_names))\"",
                            )
                        end
                    end
                end
            end
            ###################################################################
            # Migration #######################################################
            if options.migration
                migrate!(
                    bestPops.members => cur_pop, options; frac=options.fraction_replaced
                )
            end
            if options.hof_migration && length(dominating) > 0
                migrate!(dominating => cur_pop, options; frac=options.fraction_replaced_hof)
            end
            ###################################################################

            cycles_remaining[j] -= 1
            if cycles_remaining[j] == 0
                break
            end
            worker_idx = next_worker(worker_assignment, procs)
            if parallelism == :multiprocessing
                worker_assignment[(j, i)] = worker_idx
            end
            @recorder begin
                key = "out$(j)_pop$(i)"
                iteration = find_iteration_from_record(key, record) + 1
            end

            c_rss = deepcopy(all_running_search_statistics[j])
            c_cur_pop = copy_population(cur_pop)
            allPops[j][i] = @sr_spawner parallelism worker_idx let
                cur_record = RecordType()
                @recorder cur_record[key] = RecordType(
                    "iteration$(iteration)" => record_population(c_cur_pop, options)
                )
                tmp_num_evals = 0.0
                normalize_frequencies!(c_rss)
                # TODO: Could the dataset objects themselves be modified during the search??
                # Perhaps inside the evaluation kernels?
                # It shouldn't be too expensive to copy the dataset.
                tmp_pop, tmp_best_seen, evals_from_cycle = s_r_cycle(
                    dataset,
                    c_cur_pop,
                    options.ncycles_per_iteration,
                    curmaxsize,
                    c_rss;
                    verbosity=verbosity,
                    options=options,
                    record=cur_record,
                )
                tmp_num_evals += evals_from_cycle
                tmp_pop, evals_from_optimize = optimize_and_simplify_population(
                    dataset, tmp_pop, options, curmaxsize, cur_record
                )
                tmp_num_evals += evals_from_optimize

                # Update scores if using batching:
                if options.batching
                    for i_member in 1:(options.maxsize + MAX_DEGREE)
                        if tmp_best_seen.exists[i_member]
                            score, result_loss = score_func(
                                dataset, tmp_best_seen.members[i_member], options
                            )
                            tmp_best_seen.members[i_member].score = score
                            tmp_best_seen.members[i_member].loss = result_loss
                            tmp_num_evals += 1
                        end
                    end
                end

                (tmp_pop, tmp_best_seen, cur_record, tmp_num_evals)
            end
            if parallelism in (:multiprocessing, :multithreading)
                tasks[j][i] = @async put!(channels[j][i], fetch(allPops[j][i]))
            end

            cycles_elapsed = total_cycles - cycles_remaining[j]
            if options.warmup_maxsize_by > 0
                fraction_elapsed = 1.0f0 * cycles_elapsed / total_cycles
                if fraction_elapsed > options.warmup_maxsize_by
                    curmaxsizes[j] = options.maxsize
                else
                    curmaxsizes[j] =
                        3 + floor(
                            Int,
                            (options.maxsize - 3) * fraction_elapsed /
                            options.warmup_maxsize_by,
                        )
                end
            end
            stop_work_monitor!(resource_monitor)
            move_window!(all_running_search_statistics[j])
            if progress
                head_node_occupation = estimate_work_fraction(resource_monitor)
                update_progress_bar!(
                    progress_bar,
                    only(hallOfFame),
                    only(datasets),
                    options,
                    equation_speed,
                    head_node_occupation,
                    parallelism,
                )
            end
        end
        sleep(1e-6)

        ################################################################
        ## Search statistics
        elapsed_since_speed_recording = time() - last_speed_recording_time
        if elapsed_since_speed_recording > 1.0
            num_evals_since_last, num_evals_last = let s = sum(sum, num_evals)
                s - num_evals_last, s
            end
            current_speed = num_evals_since_last / elapsed_since_speed_recording
            push!(equation_speed, current_speed)
            average_over_m_measurements = 20 # 20 second running average
            if length(equation_speed) > average_over_m_measurements
                deleteat!(equation_speed, 1)
            end
            last_speed_recording_time = time()
        end
        ################################################################

        ################################################################
        ## Printing code
        elapsed = time() - last_print_time
        # Update if time has passed
        if elapsed > print_every_n_seconds
            if verbosity > 0 && !progress && length(equation_speed) > 0

                # Dominating pareto curve - must be better than all simpler equations
                head_node_occupation = estimate_work_fraction(resource_monitor)
                print_search_state(
                    hallOfFame,
                    datasets;
                    options,
                    equation_speed,
                    total_cycles,
                    cycles_remaining,
                    head_node_occupation,
                    parallelism,
                    width=options.terminal_width,
                )
            end
            last_print_time = time()
        end
        ################################################################

        ################################################################
        ## Early stopping code
        if any((
            check_for_loss_threshold(hallOfFame, options),
            check_for_user_quit(stdin_reader),
            check_for_timeout(start_time, options),
            check_max_evals(num_evals, options),
        ))
            break
        end
        ################################################################
    end

    close_reader!(stdin_reader)

    # Safely close all processes or threads
    if parallelism == :multiprocessing
        we_created_procs && rmprocs(procs)
    elseif parallelism == :multithreading
        for j in 1:nout, i in 1:(options.populations)
            wait(allPops[j][i])
        end
    end

    ##########################################################################
    ### Distributed code^
    ##########################################################################

    @recorder json3_write(record, options.recorder_file)

    if should_return_state
        return (returnPops, (dim_out == 1 ? only(hallOfFame) : hallOfFame))
    else
        return (dim_out == 1 ? only(hallOfFame) : hallOfFame)
    end
end

include("MLJInterface.jl")
import .MLJInterfaceModule: SRRegressor, MultitargetSRRegressor

function __init__()
    @require_extensions
end

macro ignore(args...) end
# Hack to get static analysis to work from within tests:
@ignore include("../test/runtests.jl")

include("precompile.jl")
redirect_stdout(devnull) do
    redirect_stderr(devnull) do
        do_precompilation(Val(:precompile))
    end
end

end #module SR
