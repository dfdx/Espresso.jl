
let
    iex = quote
        t1[i] = W[i,j] * x[j]
        t2[i] = exp(t1[i])
        y = t2[i]
    end
    ex = sanitize(from_einstein(iex))
    expected = sanitize(quote 
        t1 = W * x
        t2 = exp.(t1)
        y = squeeze(sum(t2, 1), 1)
    end)
    
    @test ex == expected
end
