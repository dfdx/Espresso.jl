
let
    iex = quote
        t1[i] = W[i,j] * x[j]
        t2[i] = exp(t1[i])
        y = t2[i]
    end
    ex = sanitize(from_einstein(iex; W=rand(3,2), x=rand(2)))
    expected = sanitize(quote
        t1 = W * x
        y = sum(exp.(t1))
    end)

    @test ex == expected
end
