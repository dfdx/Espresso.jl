
__precompile__()

module Espresso

export
    # utils
    ExH,    
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
    get_vars,
    get_var_names,
    get_indices,
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
    propagate_size!


include("core.jl")

end
