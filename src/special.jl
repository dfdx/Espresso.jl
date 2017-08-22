
const SPECIAL_FUNCS = Set{Any}()


isspecial(op) = op in SPECIAL_FUNCS

is_special_expr(ex::Expr) = any(idxs == [:(:)] for idxs in find_indices(ex))
is_special_expr(x) = false
