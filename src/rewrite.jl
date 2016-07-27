
## expression pattern matching

isplaceholder(x) = false
isplaceholder(x::Symbol) = startswith(string(x), "_")

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

function Base.match(pattern::Expr, ex::Expr)
    m = Dict{Symbol,Any}()
    res = match!(m, pattern, ex)
    if res
        return Nullable(m)
    else
        return Nullable{Dict{Symbol,Any}}()
    end
end


## symbolic substitution

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


function rewrite(ex::Expr, pattern::Expr, subex::Expr)
    st = match(pattern, ex)
    if isnull(st)
        error("Expression $ex doesn't match pattern $pattern")
    else
        return subs(subex, get(st))
    end
end

