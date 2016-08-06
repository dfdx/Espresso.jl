
@test rdiff(:(z = x1*x2 + sin(x1)), x1=1, x2=1) == [:(x2 + cos(x1)), :x1]
