using MAT, LinearAlgebra, Statistics, Optim
include(ARGS[1]); using .blp
d = matread("/Users/erickom/Documents/GitHub/problem-set-io/code/build/input/public/simulation/100markets3products.mat")
J, T = size(d["P_opt"])
p = reshape(d["P_opt"], (T*J,1)); sh = reshape(d["shares"], (T*J,1))
m = blp.BLPDemand(BLPData=blp.BLPData(T, J, d["x1"], p, sh, log.(d["alphas"] .- 1)))
pb = blp.compute_hausman(m); Xr = blp.compute_blp(m)
m.Z = hcat(m.X, pb, Xr); m.W = inv(m.Z'*m.Z)
NS = parse(Int, ARGS[2])
t = @elapsed blp.estimate_blp!(m; Ns=NS, toler=1e-10, iterations=100)
println("threads=", Threads.nthreads(), " RESULT T=$T J=$J time=$(round(t,digits=1))s")
println("params (beta..., sigma) = ", round.(vec(m.params), digits=5))
println("se = ", round.(sqrt.(abs.(diag(m.Var))), digits=5))
println("objective = ", Optim.minimum(m.opt_res[1]))
