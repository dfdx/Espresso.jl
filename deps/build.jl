
try
    Pkg.installed("Matcha")
catch 
    Pkg.clone("https://github.com/SimonDanisch/Matcha.jl.git")
end

try
    Pkg.installed("Sugar")
catch
    Pkg.clone("https://github.com/SimonDanisch/Sugar.jl.git")
end
