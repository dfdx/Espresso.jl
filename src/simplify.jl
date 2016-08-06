
const SIMPLE_RULES = Dict{Symbolic, Any}()
const SIMPLE_PHS = Set([:x])

macro simple_rule(pat, subex)
    SIMPLE_RULES[pat] = subex
    nothing
end


function tryeval(ex)
    try
        return Nullable(eval(ex))
    catch
        return Nullable()
    end
end


function simplify(ex::Expr)
    evaled = tryeval(ex)
    if !isnull(evaled)
        return get(evaled)
    else
        simplified_args = [simplify(arg) for arg in ex.args]
        ex_new_args = Expr(ex.head, simplified_args...)
        for (pat, subex) in SIMPLE_RULES
            st = matchex(pat, ex_new_args; phs=SIMPLE_PHS)
            if !isnull(st)
                return rewrite(ex_new_args, pat, subex; phs=SIMPLE_PHS)
            end
        end
        return ex_new_args
    end
end

# fallback for non-expressions
simplify(x) = x



@simple_rule (x * 1) x
@simple_rule (1 * x) x
@simple_rule (2 - 1) 1
@simple_rule (x ^ 1) x
