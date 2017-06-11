
flip{T}(X::Matrix{T}) = flipdim(flipdim(X, 1), 2)
sumsqueeze{T,N}(A::Array{T,N}, dim::Integer) = squeeze(sum(A, dim), dim)
