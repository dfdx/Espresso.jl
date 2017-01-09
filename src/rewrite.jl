
# rewrite.jl - expression pattern matching and rewriting.
#
# The general idea behind functions in this file is to provide easy means
# of finding specific pieces of expressions and using them elsewhere.
# At the time of writing it is used in 2 parts of this package:
#
# * for applyging derivatives, e.g. `x^n` ==> `n*x^(n-1)`
# * for expression simplification, e.g. `1 * x` ==> `x`
#
# Pieces of expression are matched to so-called placeholders - symbols that either
# start with `_` (e.g. `_x`) or are passed via `phs` paraneter, or set globally
# using `set_default_placeholders(::Set{Symbol})`. Using list of placeholders
# instead of _-prefixed names is convenient when writing a lot of transformation
# rules where using underscores creates unnecessary noise.


## pat matching

const DEFAULT_PHS = [Set{Symbol}()]
set_default_placeholders(set::Set{Symbol}) = (DEFAULT_PHS[1] = set)

isplaceholder(x, phs) = false
isplaceholder(x::Symbol, phs) = (startswith(string(x), "_")
                                 || in(x, phs))


function matchex!(m::Dict{Symbol,Any}, p::QuoteNode, x::QuoteNode;
                  phs=DEFAULT_PHS[1], allow_ex=true)
    return matchex!(m, p.value, x.value)
end


function matchex!(m::Dict{Symbol,Any}, p, x; phs=DEFAULT_PHS[1], allow_ex=true)
    if isplaceholder(p, phs)
        if haskey(m, p) && m[p] != x
            # different bindings to the same pattern, treat as no match
            return false
        elseif !allow_ex && isa(x, Expr)
            # x is expression, but matching to expression is not allowed, treat as no match
            return false
        else
            m[p] = x
            return true
        end
    elseif isa(p, Expr) && isa(x, Expr)
        result = (matchex!(m, p.head, x.head)
                  && length(p.args) == length(x.args)
                  && reduce(&, [matchex!(m, pa, xa; phs=phs, allow_ex=allow_ex)
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
ex = :(u ^ v)
pat = :(_x ^ _n)
matchex(pat, ex)
# ==> Nullable(Dict{Symbol,Any}(:_n=>:v,:_x=>:u))
```

NOTE: two symbols match if they are equal or symbol in pattern is a placeholder.
Placeholder is any symbol that starts with '_'. It's also possible to pass
list of placeholder names (not necessarily starting wiht '_') via `phs` parameter:

```
ex = :(u ^ v)
pat = :(x ^ n)
matchex(pat, ex; phs=Set([:x, :n]))
# ==> Nullable(Dict{Symbol,Any}(:n=>:v,:x=>:u))
```

"""
function matchex(pat, ex; phs=DEFAULT_PHS[1], allow_ex=true)
    m = Dict{Symbol,Any}()
    res = matchex!(m, pat, ex; phs=phs, allow_ex=allow_ex)
    if res
        return Nullable(m)
    else
        return Nullable{Dict{Symbol,Any}}()
    end
end

"""
Check if expression matches pattern. See `matchex()` for details.
"""
function matchingex(pat, ex; phs=DEFAULT_PHS[1], allow_ex=true)
    return !isnull(matchex(pat, ex; phs=phs, allow_ex=allow_ex))
end

## substitution

"""
Substitute symbols in `ex` according to substitute table `st`.
Example:

    ex = :(x ^ n)
    subs(ex, x=2)  # ==> :(2 ^ n)
"""
function subs(ex::Expr, st::Dict)
    if haskey(st, ex)
        return st[ex]
    else
        # new_args = [isa(arg, Expr) ? subs(arg, st) : get(st, arg, arg)
        #             for arg in ex.args]
        new_args = [subs(arg, st) for arg in ex.args]
        return Expr(ex.head, new_args...)
    end
end

function subs(s::Symbol, st::Dict)
    return haskey(st, s) ? st[s] : s
end

subs(q::QuoteNode, st::Dict) = QuoteNode(subs(q.value, st))
subs(x::Any, st::Dict) = x
subs(ex; st...) = subs(ex, Dict(st))


## remove subexpression

"""
Remove subexpression conforming to a pattern.
Example:

    ex = :(x * (m == n))
    pat = :(_i == _j)
    ex = without(ex, pat)  # ==> :x
"""
function without(ex::Expr, pat; phs=DEFAULT_PHS[1])
    new_args_without = [without(arg, pat; phs=phs) for arg in ex.args]
    new_args = filter(arg -> isnull(matchex(pat, arg; phs=phs)), new_args_without)
    if ex.head == :call && length(new_args) == 2 &&
        (ex.args[1] == :+ || ex.args[1] == :*)
        # pop argument of now-single-valued operation
        # TODO: make more general, e.g. handle (x - y) with x removed
        return new_args[2]
    else
        return Expr(ex.head, new_args...)
    end
end

without(x, pat; phs=DEFAULT_PHS[1]) = x

## rewriting

"""
Rewrite expression `ex` according to a transform from pattern `pat`
to a substituting expression `subex`.
Example (derivative of x^n):

    ex = :(u ^ v)
    pat = :(_x ^ _n)
    subex = :(_n * _x ^ (_n - 1))
    rewrite(ex, pat, subex) # ==> :(v * u ^ (v - 1))
"""
function rewrite(ex::Symbolic, pat::Symbolic, subex::Any; phs=DEFAULT_PHS[1])
    st = matchex(pat, ex; phs=phs)
    if isnull(st)
        error("Expression $ex doesn't match pattern $pat")
    else
        return subs(subex, get(st))
    end
end

"""
Same as rewrite, but returns Nullable{Expr} and doesn't throw an error
when expression doesn't match pattern
"""
function tryrewrite(ex::Symbolic, pat::Symbolic, subex::Any; phs=DEFAULT_PHS[1])
    st = matchex(pat, ex; phs=phs)
    if isnull(st)
        return Nullable{Expr}()
    else
        return Nullable(subs(subex, get(st)))
    end
end


"""
Find sub-expressions matching a pattern. Example:

    ex = :(a * f(x) + b * f(y))
    pat = :(f(_))
    findex(pat, ex)   # ==> [:(f(x)), :(f(y))]
    
"""
function findex!(res::Vector, pat, ex; phs=DEFAULT_PHS[1])
    if matchingex(pat, ex; phs=phs)
        push!(res, ex)
    elseif exprlike(ex)
        for arg in ex.args
            findex!(res, pat, arg)
        end
    end
end


function findex(pat, ex)
    res = Any[]
    findex!(res, pat, ex)
    return res
end
