
__precompile__()

module Espresso

export
    # utils
    ExH,
    to_block,
    # rewrite
    matchex,
    findex,
    subs,
    rewrite,
    tryrewrite,
    without,
    set_default_placeholders,
    # simplification
    simplify,
    @simple_rule,
    # funexpr
    funexpr,
    # indexing
    split_indexed,
    make_indexed,
    with_indices,
    get_vars,
    get_var_names,
    get_indices,
    forall_sum_indices,
    forall_indices,
    sum_indices,
    get_guards,
    without_guards,
    # ExNode
    ExNode,
    category,
    variable,
    variable!,
    varname,
    varidxs,
    expr,
    expr!,
    guards,
    guards!,
    value,
    value!,
    dependencies,
    to_expr,
    isindexed,
    # ExGraph core
    ExGraph,
    parse!,
    evaluate!,
    # ExGraph utils
    propagate_size!,
    collect_deps,
    expand_deps,
    expand_temp,
    # expr utils
    mergeex,
    optimize,
    sanitize,
    # Einstein conversions
    to_einstein,
    from_einstein



include("core.jl")

end
