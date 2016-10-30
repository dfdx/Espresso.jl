
@test isindexed(:A) == false
@test isindexed(:(A * B)) == false
@test isindexed(:(A[i] * B[i])) == true
@test isindexed(:(A * (B[i] + C[i]))) == true

@test forall_indices(:(A[i,k] * B[k,j])) == [:i,:j]
@test sum_indices(:(A[i,k] * B[k,j])) == [:k]
@test forall_indices(:(A[i,j] * b[j])) == [:i]
@test sum_indices(:(A[i,j] * b[j])) == [:j]

@test forall_indices(:(A[i,j] + B[i,j])) == [:i, :j]
@test sum_indices(:(A[i,j] + B[i,j])) == Symbol[]
@test forall_indices(:(exp(A[i]))) == [:i]
@test sum_indices(:(exp(A[i]))) == []
