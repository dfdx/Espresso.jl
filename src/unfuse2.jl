## copied from https://github.com/MikeInnes/TakingBroadcastSeriously.jl
## added some functions that need broadcasting

import Base: ^
using Base.Broadcast: broadcast_c, containertype

broadcast_(f, A, Bs...) = broadcast_c(f, containertype(A, Bs...), A, Bs...)

struct Broadcasted{T}
  x::T
end

unwrap(w::Broadcasted) = w.x

# We must hack each function we want to use with un-fused broadcasting.
for f in :[sin, cos, +, -, *, /, %, ^, <, <=, >, >=, !=, ==].args
  @eval Base.$f(a::Broadcasted...) = Broadcasted(broadcast_($f, unwrap.(a)...))

  #sometimes literals "resist" wrapping, so catch them too
  @eval Base.$f(a::Broadcasted, b) = Broadcasted(broadcast_($f, unwrap(a), b))
  @eval Base.$f(b, a::Broadcasted) = Broadcasted(broadcast_($f, b, unwrap(a)))
end

#Avoid ambiguitity with Base
^(a::Broadcasted, b::Integer) = Broadcasted(broadcast_(^, unwrap(a), b))

macro unfuse(T)
  T = esc(T)
  quote
    Base.broadcast(f, A::$T, Bs...) = f(Broadcasted(A), Broadcasted.(Bs)...) |> unwrap
    Base.broadcast(f, A, B::$T, Cs...) = f(Broadcasted(A), Broadcasted(B), Broadcasted.(Cs)...) |> unwrap
    Base.broadcast(f, A::$T, B::$T, Cs...) = f(Broadcasted(A), Broadcasted(B), Broadcasted.(Cs)...) |> unwrap
  end
end


@unfuse TrackedArray


# ## tests






# function broadcast_(::typeof(sin), xs::TrackedArray)
#   push!(blist, sin)
#   TrackedArray(sin.(xs.val))
# end

# function broadcast_(::typeof(cos), xs::TrackedArray)
#   push!(blist, cos)
#   TrackedArray(cos.(xs.val))
# end


# function broadcast_(::typeof(+), A::TrackedArray, B::TrackedArray)
#     val = A.val .+ B.val
#     var = genname()
#     nd = ExNode{:call}(var, :($(A.var) .+ $(B.var)))
#     push!(A.graph, nd)
#     return TrackedArray(var, val)
# end



# function main()
#     g = reset_default_graph()
#     a = TrackedReal(:a, 1.0)
#     b = TrackedReal(:b, 2.0)
#     c = a * b + a
#     println(g)

#     g = ExGraph()
#     A  = TrackedArray(g, :A, rand(3,4))
#     B  = TrackedArray(g, :B, rand(4,3))
#     C = A * B
#     println(g)
# end


