
@tracking +(x::TReal, y::TReal)
@tracking -(x::TReal, y::TReal)
@tracking *(x::TReal, y::TReal)
@tracking /(x::TReal, y::TReal)

@tracking -(x::TReal)
# @tracking (Base.:<=)(x::TReal, y::TReal)
# @tracking (Base.:>)(x::TReal, y::TReal)
# @tracking (Base.:>=)(x::TReal, y::TReal)
# @tracking (Base.:<)(x::TReal, y::TReal)

@tracking sin(x::TReal)
@tracking cos(x::TReal)
@tracking exp(x::TReal)
@tracking log(x::TReal)
@tracking abs(x::TReal)
@tracking abs2(x::TReal)

@tracking *(x::TArray, y::TArray)
@tracking maximum(x::TArray)

@tracking getindex(x::TArray, i::Integer)
@tracking getindex(x::TArray, i::Integer, j::Integer)
@tracking getindex(x::TArray, i::Integer, j::Integer, k::Integer)
@tracking getindex(x::TArray, i::Integer, j::Integer, k::Integer, l::Integer)

@tracking reshape(x::TArray, dims::Tuple{Int})
@tracking reshape(x::TArray, dims::Tuple{Int, Int})
@tracking reshape(x::TArray, dims::Tuple{Int, Int, Int})
@tracking reshape(x::TArray, dims::Tuple{Int, Int, Int, Int})
@tracking reshape(x::TArray, dims::Tuple{Int, Int, Int, Int, Int})
@tracking reshape(x::TArray, dims::Tuple{Int, Int, Int, Int, Int, Int})

@tracking transpose(x::TArray)

@tracking sum(x::TArray)
@tracking mean(x::TArray)

@tracking sin.(x::TArray)
@tracking cos.(x::TArray)
@tracking exp.(x::TArray)
@tracking log.(x::TArray)
@tracking log.(b::Integer, x::TArray)

# TODO: make @nontracked macro?
# boolean operators aren't tracked
for op in [:<, :<=, :>, :>=, :(==)]
    @eval (Base.$op)(x::TReal, y::TReal) = $op(x.val, y.val)
end

# mul!

function LinearAlgebra.mul!(C::TArray, A::TArray, B::TArray)
    mul!(C.val, A.val, B.val)
    nd = ExNode{:call}(C.var, :($(A.var) * $(B.var)); val=C.val)
    push!(A.graph, nd)
    return TArray(C.var, C.val)
end


# I couldn't find a way to overload .+ and friends as either call or broadcasting
# fortunately, the list of such unusual operations is small and fixed
function Broadcast.broadcasted(::typeof(+), x::TArray, y::TArray)
    val = x.val .+ y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .+ $(y.var)); val=val)
    push!(x.graph, nd)
    return TArray(var, val)
end
function Broadcast.broadcasted(::typeof(-), x::TArray, y::TArray)
    val = x.val .- y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .- $(y.var)); val=val)
    push!(x.graph, nd)
    return TArray(var, val)
end
function Broadcast.broadcasted(::typeof(*), x::TArray, y::TArray)
    val = x.val .* y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .* $(y.var)); val=val)
    push!(x.graph, nd)
    return TArray(var, val)
end
function Broadcast.broadcasted(::typeof(/), x::TArray, y::TArray)
    val = x.val ./ y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) ./ $(y.var)); val=val)
    push!(x.graph, nd)
    return TArray(var, val)
end


# TStruct

function Base.getproperty(x::TStruct, name::Symbol)
    val = getfield(getfield(x, :val), name)
    tv = tracked(getfield(x, :graph), genname(), val)
    nd = ExNode{:field}(getfield(tv, :var), Expr(:., getfield(x, :var), QuoteNode(name)); val=val)
    push!(getfield(x, :graph), nd)
    return tv
end
