
const SIMPLE_RULES = Dict{Symbolic, Any}()

macro simple_rule(pat, subex)
    SIMPLE_RULES[pat] = subex
    nothing
end

# TODO: make recursive
function simplify(ex::Expr)
    simplified_args = [simplify(arg) for arg in ex.args]
    ex_new_args = Expr(ex.head, simplified_args...)
    for (pat, subex) in SIMPLE_RULES       
        st = matchex(pat, ex_new_args)
        if !isnull(st)
            return rewrite(ex_new_args, pat, subex)        
        end        
    end       
    return ex_new_args
end

# fallback for non-expressions
simplify(x) = x


@simple_rule (x * 1) x
@simple_rule (1 * x) x
@simple_rule (2 - 1) 1
@simple_rule (x ^ 1) x
