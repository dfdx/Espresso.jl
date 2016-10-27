
@test is_indexed(:A) == false
@test is_indexed(:(A * B)) == false
@test is_indexed(:(A[i] * B[i])) == true
@test is_indexed(:(A * (B[i] + C[i]))) == true

@test forall_and_sum_indexes(:(A[i,k] * B[k,j])) == ([:i,:j], [:k])
@test forall_and_sum_indexes(:(A[i,j] * b[j])) == ([:i], [:j])
@test forall_and_sum_indexes(:(A[i,j] + B[i,j])) == ([:i, :j], [])
@test forall_and_sum_indexes(:(exp(A[i]))) == ([:i], [])
