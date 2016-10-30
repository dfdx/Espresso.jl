
# core.jl - single place to load all package definitions.
#
# If you are willing to learn the package structure, just go through
# included files one by one, read header notes and other comments

using DataStructures
using Iterators
using Einsum
using Compat

include("core/utils.jl")
include("core/types.jl")
include("core/rewrite.jl")
include("core/simplify.jl")
include("core/ops.jl")
include("core/funexpr.jl")
include("core/exgraph.jl")
include("einstein/base.jl")
include("einstein/conversions.jl")
# include("einstein/conversions2.jl")
include("diff/deriv.jl")
include("diff/rules.jl")
include("diff/tderiv.jl")
include("diff/trules.jl")
include("diff/rdiff.jl")
include("diff/tdiff.jl")
