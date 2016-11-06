
dexs = tdiff(:(W * x + b), W=rand(2, 3), x=rand(3), b=rand(2))
@test dexs == Dict(:W => sanitize(:(dtmp2[i] / dW[m,n] = x[n] * (i == m))),
                   :b => sanitize(:(dtmp2[i] / db[k] = 1.0 * (i == k))),
                   :x => sanitize(:(dtmp2[i] / dx[m] = W[i,m])))


# tdiff(:(relu(x)), x=rand(3))
