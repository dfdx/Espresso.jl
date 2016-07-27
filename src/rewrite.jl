
## pattern matching

# PH is a constant, but we can modify contained value
const PH = ["_"]

set_placeholder_prefix(ph::AbstractString) = PH[1] = ph

isplaceholder(x) = false
isplaceholder(x::Symbol) = startswith(string(x), PH[1])

function match!(m::Dict{Symbol,Any}, p, x)
    if isplaceholder(p)
        m[p] = x
        return true
    elseif isa(p, Expr) && isa(x, Expr)
        result = (match!(m, p.head, x.head) &&
                  reduce(&, [match!(m, pa, xa)
                             for (pa, xa) in zip(p.args, x.args)]))
    else
        return p == x
    end
end


"""
Match expression `ex` to a `pattern`, return nullable dictionary of matched
symbols or subexpressions.
Example:

    ex = :(num1 ^ num2)
    pattern = :(_x ^ _n)
    match(pattern, ex)  # ==> Nullable(Dict{Symbol,Any}(:_n=>:num2,:_x=>:num1))

By default, `match` uses `_` as a prefix for placeholders to match against, but
it may also be configured using function `set_placeholder_prefix(ph)`.
"""
function Base.match(pattern::Expr, ex::Expr)
    m = Dict{Symbol,Any}()
    res = match!(m, pattern, ex)
    if res
        return Nullable(m)
    else
        return Nullable{Dict{Symbol,Any}}()
    end
end


## substitution

"""
Substitute symbols in `ex` according to substitute table `st`.
Example:
    ex = :(x ^ n)
    subs(ex, x=2)  # gives :(2 ^ n)
"""
function subs(ex::Expr, st::Dict)
    new_args = [isa(arg, Expr) ? subs(arg, st) : get(st, arg, arg)
                for arg in ex.args]
    new_ex = Expr(ex.head, new_args...)
    return new_ex
end

subs(ex::Expr; st...) = subs(ex, Dict(st))


## rewriting

"""
Rewrite expression `ex` according to a transform from `pattern`
to a substituting expression `subex`.
Example (derivative of x^n):

    ex = :(num1 ^ num2)
    pattern = :(_x ^ _n)
    subex = :(_n * _x ^ (_n - 1))
    rewrite(ex, pattern, subex) # ==> :(num2 * num1 ^ (num2 - 1))
"""
function rewrite(ex::Expr, pattern::Expr, subex::Expr)
    st = match(pattern, ex)
    if isnull(st)
        error("Expression $ex doesn't match pattern $pattern")
    else
        return subs(subex, get(st))
    end
end

