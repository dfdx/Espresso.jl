
@test rdiff(:(z = x1*x2 + sin(x1)), x1=1, x2=1) == [:(x2 + cos(x1)), :x1]
    
logistic(x) = 1 / (1 + exp(-x))
dlogistic(x) = logistic(x) * (1 - logistic(x))
dlogistic_expr = rdiff(logistic; x=1)[1]
x = 5
@test isapprox(eval(dlogistic_expr), dlogistic(x))

@test (rdiff(:(x + logistic(x)), x=1) ==
       [:(1.0 + exp(-x) * (1 + exp(-x)) ^ -2)])
           

function multi(x)
    y = 2x
    z = y^2
    return z
end

@test rdiff(multi, x=1) == [:(8x)]
