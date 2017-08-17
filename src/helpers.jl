
flip(X::Matrix{T}) where {T} = flipdim(flipdim(X, 1), 2)
sumsqueeze(A::Array{T,N}, dim::Integer) where {T,N} = squeeze(sum(A, dim), dim)
