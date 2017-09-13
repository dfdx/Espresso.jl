
__precompile__()

module Espresso

export
    # utils
    ExH,
    to_block,
    # rewrite
    matchex,
    matchingex,
    findex,
    subs,
    rewrite,
    tryrewrite,
    rewrite_all,
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
    find_vars,
    find_var_names,
    find_indices,
    forall_sum_indices,
    forall_indices,
    sum_indices,
    find_guards,
    with_guards,
    without_guards,
    # ExNode
    ExNode,
    getcategory,
    getvar,
    setvar!,
    varname,
    varidxs,
    getexpr,
    setexpr!,
    getguards,
    setguards!,
    getvalue,
    setvalue!,
    indexof,
    dependencies,
    to_expr,
    isindexed,
    # ExGraph/EinGraph core
    AbstractExGraph,
    ExGraph,
    EinGraph,
    parse!,
    reparse,
    evaluate!,
    cat,
    fuse_assigned,
    # ExGraph/EinGraph utils
    dependents,
    external_vars,
    topsort,
    propagate_size!,
    collect_deps,
    expand_deps,
    expand_temp,
    expand_const,
    remove_unused,
    eliminate_common,
    # expr utils
    mergeex,
    optimize,    
    sanitize,
    # Einstein conversions
    to_einstein,
    from_einstein,
    to_buffered,
    # helpers
    sum_1,
    sum_2,
    squeeze_sum,
    squeeze_sum_1,
    squeeze_sum_2



include("core.jl")

end
