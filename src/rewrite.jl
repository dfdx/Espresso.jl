
## pat matching

const DEFAULT_PHS = [Set{Symbol}()]
set_default_placeholders(set::Set{Symbol}) = (DEFAULT_PHS[1] = set)

isplaceholder(x, phs) = false
isplaceholder(x::Symbol, phs) = (startswith(string(x), "_")
                                 || in(x, phs))

function matchex!(m::Dict{Symbol,Any}, p, x; phs=DEFAULT_PHS[1])
    if isplaceholder(p, phs)
        m[p] = x
        return true
    elseif isa(p, Expr) && isa(x, Expr)
        result = (matchex!(m, p.head, x.head)
                  && length(p.args) == length(x.args)
                  && reduce(&, [matchex!(m, pa, xa; phs=phs)
                             for (pa, xa) in zip(p.args, x.args)]))
    else
        return p == x
    end
end


"""
Match expression `ex` to a pattern `pat`, return nullable dictionary of matched
symbols or subexpressions.
Example:

```
ex = :(num1 ^ num2)
pat = :(x ^ n)
matchex(pat, ex)  # ==> Nullable(Dict{Symbol,Any}(:n=>:num2,:x=>:num1))
```

NOTE: two symbols match if they are equal or symbol in pat is a placeholder.
Placeholder is any symbol that starts with '-' or one of special symbols, stored
in a constant DEFAULT_PHS. Currently they are:
$(collect(DEFAULT_PHS))

"""
function matchex(pat::Symbolic, ex::Symbolic; phs = DEFAULT_PHS[1])
    m = Dict{Symbol,Any}()
    res = matchex!(m, pat, ex; phs=phs)
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

function subs(s::Symbol, st::Dict)
    return haskey(st, s) ? st[s] : s
end

function subs(s::Any, st::Dict)
    return s
end

subs(ex; st...) = subs(ex, Dict(st))


## rewriting

"""
Rewrite expression `ex` according to a transform from pattern `pat`
to a substituting expression `subex`.
Example (derivative of x^n):

    ex = :(num1 ^ num2)
    pat = :(_x ^ _n)
    subex = :(_n * _x ^ (_n - 1))
    rewrite(ex, pat, subex) # ==> :(num2 * num1 ^ (num2 - 1))
"""
function rewrite(ex::Symbolic, pat::Symbolic, subex::Any; phs=DEFAULT_PHS[1])
    st = matchex(pat, ex; phs=phs)
    if isnull(st)
        error("Expression $ex doesn't match pattern $pat")
    else
        return subs(subex, get(st))
    end
end
