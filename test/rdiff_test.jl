
@test rdiff(:(z = x1*x2 + sin(x1)), x1=1, x2=1) == [:(x2 + cos(x1)), :x1]

if VERSION < v"0.5-"
    
    logistic(x) = 1 / (1 + exp(-x))
    dlogistic(x) = logistic(x) * (1 - logistic(x))
    dlogistic_expr = rdiff(logistic; x=1)[1]
    x = 5
    @test isapprox(eval(dlogistic_expr), dlogistic(x))

    @test (rdiff(:(x + Main.logistic(x)), x=1) ==
           [:(1.0 + exp(-x) * (1 + exp(-x)) ^ -2)])
    
end
