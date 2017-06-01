using Espresso
using Base.Test

include("test_utils.jl")
include("rewrite_test.jl")
include("simplify_test.jl")
include("exnode_test.jl")
include("exgraph_test.jl")
include("propagate_size_test.jl")
# include("merge_test.jl")
include("einstein_test.jl")
include("to_einstein_test.jl")
include("from_einstein_test.jl")
