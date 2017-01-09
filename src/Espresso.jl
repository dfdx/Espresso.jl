
__precompile__()

module Espresso

export # ExGraph
       ExGraph,
       ExNode,
       Symbolic,
       Numeric,
       OpName,
       evaluate!,
       propagate_size!,
       expand_temp,
       dependencies,
       dep_vars,
       # rewrite
       matchex,
       subs,
       rewrite,
       tryrewrite,
       without,
       set_default_placeholders,
       # types & conversions
       ExH,
       to_expr,
       to_iexpr,
       to_exh,
       to_expr,
       to_block,
       # simplification
       simplify,
       @simple_rule,
       # einstein notation
       isindexed,
       is_einstein,
       forall_indices,
       sum_indices,
       sanitize,
       get_indices,
       with_indices,
       call_indices,
       indexed,
       maybe_indexed,
       get_guards,
       without_guards,
       from_einstein,
       to_einstein,
       # funexpr
       funexpr,
       replace_slots
       

include("core.jl")

end
