
# utils.jl - utility functions

if !isdefined(:__EXPRESSION_HASHES__)
    __EXPRESSION_HASHES__ = Set{AbstractString}()
end

"""
If loaded twice without changes, evaluate expression only for the first time.
This is useful for reloading code in REPL. For example, the following code will
produce `invalid redifinition` error if loaded twice:

    type Point{T}
        x::T
        y::T
    end

Wrapped into @runonce, however, the code is reloaded fine:

    @runonce type Point{T}
        x::T
        y::T
    end

@runonce doesn't have any affect on expression itself.
"""
macro runonce(expr)
    h = string(expr)
    return esc(quote
        if !in($h, __EXPRESSION_HASHES__)
            push!(__EXPRESSION_HASHES__, $h)
            $expr
        end
    end)
end


"""Same as `get` function, but evaluates default_expr only if needed"""
macro get(dict, key, default_expr)
    return esc(quote
        if haskey($dict, $key)
            $dict[$key]
        else
            $default_expr
        end
    end)
end


"""
Same as `@get`, but creates new object from `default_expr` if
it didn't exist before
"""
macro get_or_create(dict, key, default_expr)
    return esc(quote
        if !haskey($dict, $key)
            $dict[$key] = $default_expr
        end
        $dict[$key]
    end)
end



"""
Same as `@get`, but immediately exits function and return `default_expr`
if key doesn't exist.
"""
macro get_or_return(dict, key, default_expr)
    return esc(quote
        if haskey($dict, $key)
            $dict[$key]
        else
            return $default_expr
            nothing  # not reachable, but without it code won't compile
        end
    end)
end

"""
Get array of size `sz` from a `dict` by `key`. If element doesn't exist or
its size is not equal to `sz`, create and return new array
using `default_expr`. If element exists, but is not an error,
throw ArgumentError.
"""
macro get_array(dict, key, sz, default_expr)
    return esc(quote
        if (haskey($dict, $key) && !isa($dict[$key], Array))
            local k = $key
            throw(ArgumentError("Key `$k` exists, but is not an array"))
        end
        if (!haskey($dict, $key) || size($dict[$key]) != $sz)
            # ensure $default_expr results in an ordinary array
            $dict[$key] = convert(Array, $default_expr)
        end
        $dict[$key]
    end)
end



"""Flatten vector of vectors in-place"""
function flatten!(b::Vector, a::Vector)
    for x in a
        if isa(x, AbstractArray)
            flatten!(b, x)
        else
            push!(b, x)
        end
    end
    return b
end

"""Flatten vector of vectors"""
flatten(a::Vector) = flatten!([], a)
flatten{T}(::Type{T}, a::Vector) = convert(Vector{T}, flatten(a))

"""Flatten one level of nested vectors"""
function flatten1{T}(a::Vector{Vector{T}})
    result = Array(T, 0)
    for xs in a
        for x in xs
            push!(result, x)
        end
    end
    return result
end


function countdict{T}(a::AbstractArray{T})
    counts = OrderedDict{T, Int}()
    for x in a
        if haskey(counts, x)
            counts[x] += 1
        else
            counts[x] = 1
        end
    end
    return counts
end


unzip(coll) = map(collect, zip(coll...))


"""
Compose functins, similar to Haskell's dot operator:

    @c f g x   # ==> f(g(x))

Note that with current implementation a built-in |> operator may be used instead:

    x |> g |> f

@c may become more powerful than that, though.
"""
macro c(args...)
    ex = args[end]
    for arg in reverse(args[1:end-1])
        ex = Expr(:call, arg, ex)
    end
    return ex
end


## package-specific stuff

if VERSION < v"0.5-"
    func_name(f) = f.env.name
    func_mod(f) = f.env.module
else
    func_name(f) = Base.function_name(f)
    # func_mod(f) = Base.function_module(f)
    func_mod(f) = Base.datatype_module(typeof(f))
end


"""
Given a list of symbols such as `[:x, :y, :z]` constructs expression `x.y.z`.
This is useful for building expressions of qualified names such as
`Base.LinAlg.exp`.
"""
function dot_expr(args::Vector{Symbol})
    @assert length(args) >= 1
    if length(args) == 1
        return args[1]
    else
        ex = Expr(:., args[1], QuoteNode(args[2]))
        for i=3:length(args)
            ex = Expr(:., ex, QuoteNode(args[i]))
        end
        return ex
    end
end


"""
Return canonical representation of a function name, e.g.:

    Base.+  ==> +
    Main.+  ==> + (resolved to Base.+)
    Base.LinAlg.exp ==> exp
    Mod.foo ==> Mod.foo
"""
function canonical(mod::Module, qname)
    f = eval(mod, qname)
    mod = func_mod(f)
    name = func_name(f)
    if qname in [:.*, :./, :.+, :.-, :.^]
        return qname  # for Julia 0.6 only
    elseif mod == Base || mod == Base.Math || mod == Base.LinAlg
        return Symbol(name)
    else
        # there should be a smarter way to do it...
        parts = map(Symbol, split(string(mod), "."))
        mod_ex = dot_expr(parts)
        return Expr(:., mod_ex, QuoteNode(name))
    end
end

function canonical_calls(mod::Module, ex::Expr)
    if ex.head == :call
        new_args = [canonical_calls(mod, arg) for arg in ex.args[2:end]]
        return Expr(:call, canonical(mod, ex.args[1]), new_args...)
    else
        new_args = [canonical_calls(mod, arg) for arg in ex.args]
        return Expr(ex.head, new_args...)
    end
end

canonical_calls(mod::Module, x) = x


# context

function to_context{K,V}(d::Union{Dict{K,V},Vector{Pair{K,V}}})
    ctx = Dict{Any,Any}()
    for (k, v) in d
        ctx[k] = to_context(v)
    end
    return ctx
end

to_context(d::Dict{Any,Any}) = d
to_context(x) = x

# guards

"""create cross-reference dict of cliques"""
function cliqueset{T}(pairs::Vector{Tuple{T,T}})
    cliques = Dict{T, Set{T}}()
    for (x1, x2) in pairs
        has_x1 = haskey(cliques, x1)
        has_x2 = haskey(cliques, x2)
        if !has_x1 && !has_x2
            set = Set([x1, x2])
            cliques[x1] = set
            cliques[x2] = set
        elseif has_x1 && !has_x2
            push!(cliques[x1], x2)
            cliques[x2] = cliques[x1]
        elseif !has_x1 && has_x2
            push!(cliques[x2], x1)
            cliques[x1] = cliques[x2]
        end
    end
    return cliques
end


function reduce_equalities{T}(pairs::Vector{Tuple{T,T}}, anchors::Set{T})
    cliques = cliqueset(pairs)
    st = Dict{T,T}()
    new_pairs = Set{Tuple{T,T}}()
    for (x, ys) in cliques
        for y in ys
            if x == y
                continue
            elseif in(x, anchors) && in(y, anchors)
                # replace larger anchor with smaller one, keep pair
                mn, mx = min(x, y), max(x, y)
                st[mx] = mn
                push!(new_pairs, (mn, mx))
            elseif in(x, anchors)
                # replace non-anchor with anchor
                st[y] = x
            elseif !in(x, anchors) && !in(y, anchors)
                # replace larger anchor with smaller one
                mn, mx = min(x, y), max(x, y)
                st[mx] = mn
            end
        end
    end
    return st, [p for p in new_pairs]
end


function bcast_to_call(pex::Expr)
    @assert pex.head == :(.)
    return Expr(:call, pex.args[1], pex.args[2].args...)
end
