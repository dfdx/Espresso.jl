
# matrix-by-matrix product
@tdiff_rule (Z[i,j] = X[i,k] * Y[k,j]) (dZ[i,j]/dX[m,n] = Y[n,j] * (i == m))
@tdiff_rule (Z[i,j] = X[i,k] * Y[k,j]) (dZ[i,j]/dY[m,n] = X[i,m] * (n == j))

# matrix-by-vector product
@tdiff_rule (Z[i] = X[i,k] * Y[k]) (dZ[i]/dX[m,n] = Y[n] * (i == m))
@tdiff_rule (Z[i] = X[i,k] * Y[k]) (dZ[i]/dY[m] = X[i,m])

# pseudo summation functions
## @tdiff_rule (Z[] = X[i] * I[i]) (dZ[]/dX[j] = 1)
## @tdiff_rule (Z[] = X[i] * I[i]) (dZ[]/dI[j] = X[j])
## @tdiff_rule (Z[] = X[i,j] * I[i,j]) (dZ[]/dX[m,n] = 1)
## @tdiff_rule (Z[] = X[i,j] * I[i,j]) (dZ[]/dI[m,n] = X[m,n])

# inner product of 2 vectors
@tdiff_rule (Z = X[i] * Y[i]) (dZ[]/dX[i] = Y[i])
@tdiff_rule (Z = X[i] * Y[i]) (dZ[]/dY[i] = X[i])

# outer product of 2 vectors
@tdiff_rule (Z[i,j] = X[i] * Y[j]) (dZ[i,j]/dX[m] = Y[j] * (i == m))
@tdiff_rule (Z[i,j] = X[i] * Y[j]) (dZ[i,j]/dY[m] = X[i] * (j == m))

# inner product of 2 matrices
@tdiff_rule (Z = X[i,j] * Y[i,j]) (dZ[]/dX[i,j] = Y[i,j])
@tdiff_rule (Z = X[i,j] * Y[i,j]) (dZ[]/dY[i,j] = X[i,j])

# index permutation (broken)
# @tdiff_rule (Z[i,j] = X[j,i]) (dZ[i,j]/dX[m,n] = 1 * (i == n) * (j == m))

# some element-wise functions
@tdiff_rule (Z[i] = X[i] + Y[i]) (dZ[i]/dX[j] = 1 * (i == j))
@tdiff_rule (Z[i] = X[i] + Y[i]) (dZ[i]/dY[j] = 1 * (i == j))
@tdiff_rule (Z[i,j] = X[i,j] + Y[i,j]) (dZ[i,j]/dX[m,n] = 1 * (i == m) * (j == n))
@tdiff_rule (Z[i,j] = X[i,j] + Y[i,j]) (dZ[i,j]/dY[m,n] = 1 * (i == m) * (j == n))


