
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


const Symbolic = Union{Expr, Symbol}
const Numeric = Union{Number, Array}

## pattern matching

const DEFAULT_PHS = [Set{Symbol}()]
set_default_placeholders(set::Set{Symbol}) = (DEFAULT_PHS[1] = set)

isplaceholder(x, phs) = false
isplaceholder(x::Symbol, phs) = (startswith(string(x), "_")
                                 || in(x, phs))
# isplaceholder(ex::Expr, phs) = ex.head == :... && isplaceholder(ex.args[1], phs)

function find_key(d::Dict{K, V}, val) where {K,V}
    r = nothing
    for (k,v) in d
        if v == val
            r = k
            break
        end
    end
    return r
end


function matchex!(m::Dict{Symbol,Any}, p::QuoteNode, x::QuoteNode;
                  opts...)
    return matchex!(m, p.value, x.value)
end


function matchex!(m::Dict{Symbol,Any}, ps::Vector, xs::Vector; opts...)
    opts = to_dict(opts)
    phs = get(opts, :phs, Set([]))
    length(ps) <= length(xs) || return false
    for i in eachindex(ps)
        if isa(ps[i], Expr) && ps[i].head == :... && isplaceholder(ps[i].args[1], phs)
            p = ps[i].args[1]
            haskey(m, p) && m[p] != xs[i] && m[p] != xs[i:end] && return false
            # TODO: add something here?
            m[p] = xs[i:end]
            return true
        else
            matchex!(m, ps[i], xs[i]; opts...) || return false
        end
    end
    # matched everything, didn't encounter dots expression
    return length(ps) == length(xs)
end


function matchex!(m::Dict{Symbol,Any}, p, x; phs=DEFAULT_PHS[1], allow_ex=true, exact=false)
    allow_ex = exact ? false : allow_ex  # override allow_ex=false if exact==true
    if isplaceholder(p, phs)
        if haskey(m, p) && m[p] != x
            # different bindings to the same pattern, treat as no match
            return false
        elseif !allow_ex && isa(x, Expr)
            # x is expression, but matching to expression is not allowed, treat as no match
            return false
        elseif exact
            k = find_key(m, x)
            if k != p
                return false
            else
                m[p] = x
                return true
            end
        else                       
            m[p] = x
            return true
        end
    elseif isa(p, Expr) && isa(x, Expr)
        return (matchex!(m, p.head, x.head) &&
                matchex!(m, p.args, x.args; phs=phs, allow_ex=allow_ex, exact=exact))
    else
        return p == x
    end
end


"""
Match expression `ex` to a pattern `pat`, return nullable dictionary of matched
symbols or rpatpressions.
Example:

```
ex = :(u ^ v)
pat = :(_x ^ _n)
matchex(pat, ex)
# ==> Union{ Dict{Symbol,Any}(:_n=>:v,:_x=>:u), Void }
```

NOTE: two symbols match if they are equal or symbol in pattern is a placeholder.
Placeholder is any symbol that starts with '_'. It's also possible to pass
list of placeholder names (not necessarily starting wiht '_') via `phs` parameter:

```
ex = :(u ^ v)
pat = :(x ^ n)
matchex(pat, ex; phs=Set([:x, :n]))
# ==> Union{ Dict{Symbol,Any}(:n=>:v,:x=>:u), Void } 
```

Several elements may be matched using `...` expression, e.g.:

```
ex = :(A[i, j, k])
pat = :(x[I...])
matchex(pat, ex; phs=Set([:x, :I]))
# ==> Union{ Dict(:x=>:A, :I=>[:i,:j,:k]), Void }
```

Optional parameters:

 * phs::Set{Symbol} = DEFAULT_PHS[1]
       A set of placeholder symbols
 * allow_ex::Boolean = true
       Allow matchinng of symbol pattern to an expression. Example:

           matchex(:(_x + 1), :(a*b + 1); allow_ex=true)  # ==> matches
           matchex(:(_x + 1), :(a*b + 1); allow_ex=false)  # ==> doesn't match
 * exact::Boolean = false
       Allow matching of the same expression to different keys

           matchex(:(_x + _y), :(a + a); exact=false) # ==> matches
           matchex(:(_x = _y), :(a + a); exact=true)  # ==> doesn't match

"""
function matchex(pat, ex; opts...)
    m = Dict{Symbol,Any}()
    res = matchex!(m, pat, ex; opts...)
    if res
        return m
    else
        return nothing
    end
end

"""
Check if expression matches pattern. See `matchex()` for details.
"""
function matchingex(pat, ex; opts...)
    return matchex(pat, ex; opts...) != nothing
end


## find rpatpression

function findex!(res::Vector, pat, ex; phs=DEFAULT_PHS[1])
    if matchingex(pat, ex; phs=phs)
        push!(res, ex)
    elseif expr_like(ex)
        for arg in ex.args
            findex!(res, pat, arg; phs=phs)
        end
    end
end


"""
Find sub-expressions matching a pattern. Example:

    ex = :(a * f(x) + b * f(y))
    pat = :(f(_))
    findex(pat, ex)   # ==> [:(f(x)), :(f(y))]

"""
function findex(pat, ex; phs=DEFAULT_PHS[1])
    res = Any[]
    findex!(res, pat, ex; phs=phs)
    return res
end


## substitution

"""
Given a list of expression arguments, flatten the dotted ones. Example:

    args = [:foo, :([a, b, c]...)]
    flatten_dots(args)
    # ==> [:foo, :a, :b, :c]
"""
function flatten_dots(args::Vector)
    new_args = Vector{Any}()
    for arg in args
        if isa(arg, Expr) && arg.head == :... && isa(arg.args[1], AbstractArray)
            for x in arg.args[1]
                push!(new_args, x)
            end
        else
            push!(new_args, arg)
        end
    end
    return new_args
end


"""
Substitute symbols in `ex` according to substitute table `st`.
Example:

    ex = :(x ^ n)
    subs(ex, x=2)            # ==> :(2 ^ n)

alternatively:

    subs(ex, Dict(:x => 2))  # ==> :(2 ^ n)

If `ex` contains a :(xs...) argument and `st` contains an array-valued
sabstitute for it, the substitute will be flattened:

    ex = :(foo(xs...))
    subs(ex, Dict(:xs => [:a, :b, :c]))
    # ==> :(foo(a, b, c))
"""
function subs(ex::Expr, st::Dict)
    if haskey(st, ex)
        return st[ex]
        # elseif ex.head == :... && haskey(st, ex.args[1])        
    else
        new_args = [subs(arg, st) for arg in ex.args]
        new_args = flatten_dots(new_args)
        return Expr(ex.head, new_args...)
    end
end


function subs(s::Symbol, st::Dict)
    return haskey(st, s) ? st[s] : s
end

subs(q::QuoteNode, st::Dict) = QuoteNode(subs(q.value, st))
subs(x::Any, st::Dict) = x
subs(ex; st...) = subs(ex, to_dict(st))


## remove rpatpression

"""
Remove rpatpression conforming to a pattern.
Example:

    ex = :(x * (m == n))
    pat = :(_i == _j)
    ex = without(ex, pat)  # ==> :x
"""
function without(ex::Expr, pat; phs=DEFAULT_PHS[1])
    new_args_without = [without(arg, pat; phs=phs) for arg in ex.args]
    new_args = filter(arg -> !matchingex(pat, arg; phs=phs), new_args_without)
    if ex.head == :call && length(new_args) == 2 &&
        (ex.args[1] == :+ || ex.args[1] == :*)
        # pop argument of now-single-valued operation
        # TODO: make more general, e.g. handle (x - y) with x removed
        return new_args[2]
    elseif ex.head == :call && length(new_args) == 1 && ex.args[1] == :*
        return 1.0
    elseif ex.head == :call && length(new_args) == 1 && ex.args[1] == :+
        return 0.0
    else
        return Expr(ex.head, new_args...) |> simplify
    end
end

without(x, pat; phs=DEFAULT_PHS[1]) = x


## rewriting

"""
rewrite(ex, pat, rpat)

Rewrite expression `ex` according to a transform from pattern `pat`
to a substituting expression `rpat`.
Example (derivative of x^n):

    ex = :(u ^ v)
    pat = :(_x ^ _n)
    rpat = :(_n * _x ^ (_n - 1))
    rewrite(ex, pat, rpat) # ==> :(v * u ^ (v - 1))
"""
function rewrite(ex::Symbolic, pat::Symbolic, rpat::Any; opts...)
    st = matchex(pat, ex; opts...)
    if st == nothing
        error("Expression $ex doesn't match pattern $pat")
    else
        return subs(rpat, st)
    end
end


"""
Same as rewrite, but returns Union{Expr, Void} and doesn't throw an error
when expression doesn't match pattern
"""
function tryrewrite(ex::Symbolic, pat::Symbolic, rpat::Any; opts...)
    st = matchex(pat, ex; opts...)
    if st == nothing
        return nothing
    else
        return subs(rpat, st)
    end
end



"""
rewrite_all(ex, rules)

Recursively rewrite an expression according to a list of rules like [pat => rpat]
Example:

    ex = :(foo(bar(foo(A))))
    rules = [:(foo(x)) => :(quux(x)),
             :(bar(x)) => :(baz(x))]
    rewrite_all(ex, rules; phs=[:x])
    # ==> :(quux(baz(quux(A))))
"""
function rewrite_all(ex::Symbolic, rules; opts...)
    new_ex = ex
    if isa(ex, Expr)
        new_args = [rewrite_all(arg, rules; opts...)
                    for arg in ex.args]
        new_ex = Expr(ex.head, new_args...)
    end
    for (pat, rpat) in rules
        if matchingex(pat, new_ex; opts...)
            new_ex = rewrite(new_ex, pat, rpat; opts...)
        end
    end
    return new_ex
end


"""
rewrite_all(ex, pat, rpat)

Recursively rewrite all occurrences of a pattern in an expression.
Example:

    ex = :(foo(bar(foo(A))))
    pat = :(foo(x))
    rpat = :(quux(x))
    rewrite_all(ex, pat, rpat; phs=[:x])
    # ==> :(quux(bar(quux(A))))
"""
function rewrite_all(ex::Symbolic, pat::Symbolic, rpat; opts...)
    return rewrite_all(ex, [pat => rpat]; opts...)
end

rewrite_all(x, pat, rpat; opts...) = x
rewrite_all(x, rules; opts...) = x
