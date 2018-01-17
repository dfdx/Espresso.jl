
## tracked.jl - build ExGraph using tracked data types

# import Base: +, -, *, /, log, exp, min, max, reshape, transpose, sum, mean,
#     minimum, maximum


# const DEFAULT_GRAPH = Ref(ExGraph())

# get_default_graph() = DEFAULT_GRAPH[]
# set_default_graph(g::ExGraph) = (DEFAULT_GRAPH[] = g)
# reset_default_graph() = (DEFAULT_GRAPH[] = ExGraph())


# ## TRACKED REAL

# struct TrackedReal <: Real
#     g::ExGraph    # graph
#     n::Symbol     # name
#     v::Real       # value
# end

# TrackedReal(n::Symbol, v::Real) = TrackedReal(get_default_graph(), n, v)
# Base.show(io::IO, x::TrackedReal) = print(io, "Tracked($(x.n) = $(x.v))")
# tracked_val(g::ExGraph, n::Symbol, v::Real) = TrackedReal(g, n, v)

struct TrackedArray{T,N} <: AbstractArray{T,N}
    g::ExGraph                  # graph
    n::Symbol                   # name
    v::AbstractArray{T,N}       # value
end

TrackedArray(n::Symbol, v::AbstractArray) = TrackedArray(get_default_graph(), n, v)

Base.show(io::IO, x::TrackedArray{T,N}) where {T,N} =
    print(io, "Tracked{$T,$N}($(x.n) = $(x.v))")

# tracked_val(g::ExGraph, n::Symbol, v::AbstractArray) = TrackedArray(g, n, v)

# ## conversion and promotion


# tracked(g::ExGraph, x::TrackedReal) = x
# tracked(g::ExGraph, x::TrackedArray) = x

# function tracked(g::ExGraph, x::T) where {T <: Real}
#     var = genname()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TrackedReal(g, var, x)
# end

# function tracked(g::ExGraph, x::T) where {T <: AbstractArray}
#     var = genname()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TrackedArray(g, var, x)
# end


# value(x::TrackedArray) = x.v
# value(x::TrackedReal) = x.v
# value(x) = x

# istracked(x::TrackedReal) = true
# istracked(x::TrackedArray) = true
# istracked(x) = false


# Base.promote_rule(::Type{TrackedReal}, ::Type{<:Real}) = TrackedReal

# function Base.convert(::Type{TrackedReal}, x::R) where {R <: Real}
#     var = genname()
#     g = get_default_graph()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TrackedReal(g, var, x)
# end

# Base.convert(::Type{TrackedReal}, x::TrackedReal) = x

# ## overloaded functions

# for op in (:+, :-, :*, :/, :^, :max, :min, :log, :exp)

#     @eval function $op(xs::TrackedReal...)
#         x1 = xs[1]
#         v = $op([x.v for x in xs]...)
#         tv = tracked_val(x1.g, genname(), v)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, [x.n for x in xs]...)
#         nd = ExNode{:call}(tv.n, ex; val=v)
#         push!(x1.g, nd)
#         return tv
#     end

# end


# for op in (:+, :-, :*, :/, :^, :max, :min)

#     @eval function $op(x::TrackedReal, y::TrackedReal)
#         v = $op(x.v, y.v)
#         tv = tracked_val(x.g, genname(), v)
#         iop = Symbol($op)
#         ex = :($iop($(x.n), $(y.n)))
#         nd = ExNode{:call}(tv.n, ex; val=v)
#         push!(x.g, nd)
#         return tv
#     end

# end



## TRACKED ARRAY


# TODO: should write this to graph? presumably no
Base.size(x::TrackedArray) = size(x.v)
# TODO: and these? presumably yes, but be carefull about printing
Base.getindex(x::TrackedArray, I...) = getindex(x.v, I...)
Base.setindex!(x::TrackedArray, v, I...) = setindex!(x.v, v, I...)


## conversion and promotion

# Base.promote_rule(::Type{TrackedArray}, ::Type{<:AbstractArray}) = TrackedArray

# function Base.convert(::Type{TrackedArray}, x::A) where {A <: AbstractArray}
#     var = genname()
#     g = get_default_graph()
#     push!(g, ExNode{:constant}(var, x; val=x))
#     return TrackedArray(g, var, x)
# end

# Base.convert(::Type{TrackedArray}, x::TrackedArray) = x

## overloaded functions

# for op in (:+, :-, :*, :/, :^, :transpose, :sum, :mean, :minimum, :maximum)

#     @eval function $op(xs::TrackedArray...)
#         x1 = xs[1]
#         v = $op([x.v for x in xs]...)
#         tv = tracked_val(x1.g, genname(), v)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, [x.n for x in xs]...)
#         nd = ExNode{:call}(tv.n, ex; val=v)
#         push!(x1.g, nd)
#         return tv
#     end

# end


# for op in (+, -, *, /, ^)

#     @eval function Base.broadcast(::typeof($op), xs::TrackedArray...)
#         println("broadcasting")
#         x1 = xs[1]
#         v = $op.([x.v for x in xs]...)
#         tv = tracked_val(x1.g, genname(), v)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, [x.n for x in xs]...)
#         nd = ExNode{:call}(tv.n, ex; val=v)
#         push!(x1.g, nd)
#         return tv
#     end

# end


# for op in (:reshape, )

#     @eval function $op(x::TrackedArray, dims::Int...)
#         v = $op(x.v, dims...)
#         tv = tracked_val(x.g, genname(), v)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, x.n, dims...)
#         nd = ExNode{:call}(tv.n, ex; val=v)
#         push!(x.g, nd)
#         return tv
#     end

# end



# ## broadcasting

# Base.Broadcast._containertype(::Type{<:TrackedArray{T,N}}) where {T,N} =
#     TrackedArray{T,N}
# Base.Broadcast.promote_containertype(::Type{TrackedArray{T,N}}, _) where {T,N} =
#     TrackedArray{T,N}
# Base.Broadcast.promote_containertype(_, ::Type{TrackedArray{T,N}}) where {T,N} =
#     TrackedArray{T,N}
# Base.Broadcast.promote_containertype(::Type{TrackedArray{T,N}}, ::Type{Array}) where {T,N} =
#     TrackedArray{T,N}
# Base.Broadcast.promote_containertype(::Type{Array}, ::Type{TrackedArray{T,N}}) where {T,N} =
#     TrackedArray{T,N}

# function Base.Broadcast.broadcast_c(f, ::Type{TrackedArray{T,N}}, xs...) where {T,N}
#     A = xs[findfirst(istracked, xs)]
#     xvals = map(value, xs)
#     v = f.(xvals...)
#     tv = tracked_val(A.g, genname(), v)
#     op = Symbol(f)
#     txs = [tracked(A.g, x) for x in xs]
#     ex = :($op.($(txs...)))
#     nd = ExNode{:bcast}(tv.n, ex; val=v)
#     push!(A.g, nd)
#     return tv
# end

function main()
    g = reset_default_graph()
    a = TrackedReal(:a, 1.0)
    b = TrackedReal(:b, 2.0)
    c = a * b + a
    println(g)

    g = ExGraph()
    A  = TrackedArray(g, :A, rand(3,4))
    B  = TrackedArray(g, :B, rand(4,3))
end
