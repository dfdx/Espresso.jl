
const SIMPLE_RULES = Dict{Symbolic, Any}()
const SIMPLE_PHS = Set([:x, :y, :a, :b])

macro simple_rule(pat, subex)
    SIMPLE_RULES[pat] = subex
    nothing
end


is_calculable(x::Numeric) = true
is_calculable(x::Symbol) = false
is_calculable(ex::Expr) = (ex.head == :call
                           && reduce(&, [is_calculable(arg)
                                         for arg in ex.args[2:end]]))

tryeval(ex) = is_calculable(ex) ? Nullable(eval(ex)) : Nullable()


function _simplify(ex::Expr)
    evaled = tryeval(ex)
    if !isnull(evaled)
        return get(evaled)
    else
        simplified_args = [_simplify(arg) for arg in ex.args]
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
_simplify(x) = x

function simplify(x)
    # several rounds of simplification may be needed, so we simplify 
    # until there are no more changes to `x`, but no more than 5 times
    old_x = nothing
    rounds = 1
    while x != old_x && rounds <= 5
        old_x = x
        x = _simplify(x)
        rounds += 1
    end
    return x
end


# simplification rules

@simple_rule (x * 1) x
@simple_rule (1 * x) x
@simple_rule (x ^ 1) x
@simple_rule (a * (b * x)) ((a * b) * x)
@simple_rule ((b * x) * a) ((a * b) * x)

@simple_rule (-1 * x) -x
@simple_rule (x * -1) -x
@simple_rule (-x * -y) (x * y)
