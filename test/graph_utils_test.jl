

let
    ex = quote
        x[k] = u[k] + v[k]
        y[i] = W[i,q] * x[q]
        w[i] = u[i] + v[i]
        z[m] = W[m,n] * w[n]
        res = (y[i], z[i])
    end
    g = EinGraph(ex |> sanitize)

    eg = eliminate_common(g)
    eex = eg |> to_expr |> sanitize
    expected = quote 
        x[i] = u[i] + v[i]
        y[i] = W[i, j] * x[j]
        res = (y[i], y[i])
    end |> sanitize

    @test eex == expected
end
