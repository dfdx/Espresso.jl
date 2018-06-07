
# simplify.jl - simplify numeric expressions in Julia.
# 
# Common examples of expressions that may be simplified are multiplication
# by 1 or fully numeric expressions that may be just calculated out.
# 
# Simplification is performed by rewriting original expression according to
# a list of simplification rules defined using macro `@simple_rule`.
# This macro as well as function `simplify` are exposed to the outer world.

# TODO: check if it's possible to add new simplification rules from
# outside the module

const SIMPLE_RULES = Dict{Symbolic, Any}()
const SIMPLE_PHS = Set([:x, :y, :a, :b])

"""
Macro to add simplification rules. Example:

    @simple_rule (-x * -y) (x * y)

where `(-x * -y)` is a pattern to match expression and `(x * y)` is what
it should be transformed to (see `rewrite()` to understand expression rewriting).
Symbols $SIMPLE_PHS may be used as placeholders when defining new rules, all
other symbols will be taken literally.
"""
macro simple_rule(pat, subex)
    SIMPLE_RULES[pat] = subex
    nothing
end


is_calculable(x::Numeric) = true
is_calculable(x::Symbol) = false
is_calculable(ex::Expr) = (ex.head == :call
                           && reduce(&, [is_calculable(arg)
                                         for arg in ex.args[2:end]]))
is_calculable(c::Colon) = false

tryeval(ex) = is_calculable(ex) ? eval(ex) : nothing


function _simplify(ex::Expr)
    evaled = tryeval(ex)
    if evaled != nothing
        return evaled
    else
        simplified_args = [_simplify(arg) for arg in ex.args]
        ex_new_args = Expr(ex.head, simplified_args...)
        for (pat, subex) in SIMPLE_RULES
            if matchingex(pat, ex_new_args; phs=SIMPLE_PHS)
                return rewrite(ex_new_args, pat, subex; phs=SIMPLE_PHS)
            end
        end
        return ex_new_args
    end
end

# fallback for non-expressions
_simplify(x) = x

"""
Simplify expression `x` by applying a set of rules. Common examples of
simplification include calculation of fully numeric subexpressions, removing
needless multiplication by 1, etc.

Use macro `@simple_rule` to add new simplification rules.
"""
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
@simple_rule (x ^ 0) 1
@simple_rule (x .* 1) x
@simple_rule (1 .* x) x
@simple_rule (x .^ 1) x
@simple_rule (a * (b * x)) ((a * b) * x)

@simple_rule (-1 * x) -x
@simple_rule (x * -1) -x
@simple_rule (-x * -y) (x * y)
@simple_rule (-1 .* x) -x
@simple_rule (x .* -1) -x
@simple_rule (-x .* -y) (x .* y)


@simple_rule size(x)[1] size(x, 1)
@simple_rule size(x)[2] size(x, 2)
@simple_rule (x, y)[1] x
@simple_rule (x, y)[[1]] x
@simple_rule (x, y)[2] y
@simple_rule (x, y)[[2]] y
@simple_rule (x, y)[[1,2]] (x, y)
@simple_rule (x, y)[[2,1]] (y, x)
@simple_rule (x, y)[[]] ()
@simple_rule (size(x)...,) size(x)

# @simple_rule (x,) x
