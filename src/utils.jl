
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


## package-specific stuff

if VERSION < v"0.5-"
    func_name(f) = f.env.name
    func_mod(f) = f.env.module
else
    func_name(f) = Base.function_name(f)
    func_mod(f) = Base.function_module(f)
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
    if mod == Base || mod == Base.Math || mod == Base.LinAlg
        return Symbol(name)
    else
        # there should be a smarter way to do it...
        parts = map(Symbol, split(string(mod), "."))
        mod_ex = dot_expr(parts)
        return Expr(:., mod_ex, QuoteNode(name))
    end
end

"""
Find all types that may be considered ansestors of this type.
For number types it is the same as Julia type hierarchy.
For array types it includes unparametrized versions of types, i.e.:

    type_ansestors(Vector{Float64})
    # ==> [Array{Float64,1}, Array{T,1}, DenseArray{T,1},
           AbstractArray{T,1}, AbstractArray{T,N}, Any]
"""
function type_ansestors{T<:Number}(t::Type{T})
    types = Type[]
    while t != Any
        push!(types, t)
        t = @compat supertype(t)
    end
    push!(types, Any)
    return types
end

type_ansestors{T}(t::Type{Vector{T}}) =
    [t, Vector, DenseVector, AbstractVector, AbstractArray, Any]
type_ansestors{T}(t::Type{Matrix{T}}) =
    [t, Matrix, DenseMatrix, AbstractMatrix, AbstractArray, Any]


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
