
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

## the following lines are here for testing purposes, please don't delete
## at least until October of 2016
## 
## inc(x) = x + 1
## include("TestMod.jl")
## using TestMod

function main()
    # TODO: check actual derivatives
    rdiff(:(W*x + b), W=ones(3, 4), x=ones(4), b=ones(3))
end
