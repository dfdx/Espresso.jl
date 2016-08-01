
include("utils.jl")
include("searchtree.jl")
include("types.jl")
include("rewrite.jl")
include("simplify.jl")
include("ops.jl")
include("rdiff.jl")


function main_simple()
    ex = :(1 * (2 * x ^ (2 - 1)))
    simplify(ex)

    rdiff(:(x^2), x=1.)
end
