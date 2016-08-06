
@test simplify(:(10 - 5)) == 5
@test simplify(:(u - 2)) == :(u - 2)
@test simplify(:(1 * (u - 2))) == :(u - 2)
@test simplify(:(1.0 * cos(x1))) == :(cos(x1))
