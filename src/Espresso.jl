
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
    func_expr,
    func_name,
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
    getexpr_kw,
    setexpr!,
    getguards,
    setguards!,
    getvalue,
    setvalue!,
    indexof,
    dependencies,
    to_expr,
    to_expr_kw,
    isindexed,
    # ExGraph core
    AbstractExGraph,
    ExGraph,
    parse!,
    reparse,
    evaluate!,
    cat,
    fuse_assigned,
    # ExGraph utils
    dependents,
    external_vars,
    topsort,
    collect_deps,
    expand_deps,
    expand_const,
    remove_unused,
    eliminate_common,
    inline_nodes,
    graph_hash,
    # expr utils
    mergeex,
    sanitize,
    # conversions
    to_buffered,
    to_inplace,
    @inplacerule,
    # destruct
    make_func_expr,
    isstruct,
    field_values,
    named_field_values,
    destruct,
    destruct_inputs,
    # codegens
    generate_code,    
    VectorCodeGen,
    BufCodeGen,
    CuCodeGen,
    GPUCodeGen,
    autoselect_codegen,
    # helpers
    sum_1,
    sum_2,
    squeeze_sum,
    squeeze_sum_1,
    squeeze_sum_2,
    __construct



include("core.jl")

end
