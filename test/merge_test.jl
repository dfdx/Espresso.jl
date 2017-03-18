
let
    ex1 = quote
        x = u * v
        res1 = 2x
    end
    ex2 = quote
        y = u + v
        res2 = y + 1
    end
    ex3 = quote
        x = u * v
        y = u + v
        z = x / y
        res3 = x + y + z
    end
    merged = mergeex(ex1, ex2, ex3)
    @test length(sanitize(merged).args) == 9
    @test merged.args[end] == :((res1, res2, res3))
end


let
    ex1 = quote
        x[i,j] = u[i] .* v[j]
        res1[i,j] = 2x[i,j]
    end
    ex2 = quote
        y[i] = u[i] + v[i]
        res2[i] = y[i] + 1
    end
    ex3 = quote
        x[i,j] = u[i] .* v[j]
        y[i] = u[i] + v[i]
        res3 = x[i,j] * y[i]
    end
    merged = mergeex(ex1, ex2, ex3)
    @test length(sanitize(merged).args) == 9
    @test merged.args[end] == :((res1[i,j], res2[i], res3)) 
end
