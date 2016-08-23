
# core.jl - single place to load all package definitions.
#
# If you are willing to learn the package structure, just go through
# included files one by one, read header notes and other comments

using DataStructures
using Iterators
using Einsum
using Compat

include("utils.jl")
include("types.jl")
include("rewrite.jl")
include("simplify.jl")
include("ops.jl")
include("funexpr.jl")
include("einstein.jl")
include("deriv.jl")
include("tensor_deriv.jl")
include("diff_rules.jl")
include("exgraph.jl")
include("rdiff.jl")
