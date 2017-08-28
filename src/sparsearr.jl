
struct SparseArray{T,N} <: AbstractArray{T,N}
    data::Dict{NTuple{N,Int}, T}
    sz::NTuple{N,Int}
end


SparseArray{T}(sz::NTuple{N,Int}) where {T,N} = SparseArray{T,N}(Dict(), sz)
SparseArray{T}(sz::Int...) where {T} = SparseArray{T,length(sz)}(Dict(), sz)

Base.size(S::SparseArray{T,N}) where {T,N} = S.sz
Base.eltype(S::SparseArray{T,N}) where {T,N} = T

Base.similar(S::SparseArray{T,N}; element_type=T, dims=size(S)) where {T,N} =
    SparseArray{element_type}(dims)
Base.similar(S::SparseArray{T,N}, dims=size(S)) where {T,N} =
    similar(S; dims=dims)
Base.similar(S::SparseArray{T,N}, dims::Int...) where {T,N} =
    similar(S; dims=dims)
Base.similar(S::SparseArray{T,N}, t::Type{new_T}) where {T,N,new_T} =
    similar(S; element_type=new_T)



function Base.getindex(S::SparseArray{T,N}, inds...) where {T,N}
    if any(inds .> S.sz)
        throw(BoundsError("$(S.sz) SparseArray{$T,$N} at index $inds"))
    end
    key = (inds...)
    return get(S.data, key, zero(T))
end


function Base.setindex!(S::SparseArray{T,N}, X, inds...) where {T,N}
    if any(inds .> S.sz)
        throw(BoundsError("$(S.sz) SparseArray{$T,$N} at index $inds"))
    end
    key = (inds...)
    S.data[key] = X
end
