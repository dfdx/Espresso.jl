
flip(X::Matrix{T}) where {T} = flipdim(flipdim(X, 1), 2)

sum_1(X) = sum(X, 1)
sum_2(X) = sum(X, 2)

squeeze_sum(A::Array{T,N}, dim::Integer) where {T,N} = squeeze(sum(A, dim), dim)
squeeze_sum_1(A) = squeeze_sum(A, 1)
squeeze_sum_2(A) = squeeze_sum(A, 2)
