
const SPECIAL_FUNCS = Set{Any}([
    :(Main.foo),
    :(Main.foo_grad)
])



is_special_expr(ex::Expr) = any(idxs == [:(:)] for idxs in find_indices(ex))
is_special_expr(x) = false
