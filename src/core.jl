
using Iterators
using Compat

include("utils.jl")
include("types.jl")
include("rewrite.jl")
include("simplify.jl")
include("ops.jl")
include("diff_rules.jl")
include("funexpr.jl")
include("rdiff.jl")


function main()
    # TODO: check actual derivatives
    rdiff(:(W*x + b), W=ones(3, 4), x=ones(4), b=ones(3))

    rdiff(dot, x=rand(3), y=rand(3))
    rdiff(:(dot(x, y)), x=rand(3), y=rand(3))          
end
