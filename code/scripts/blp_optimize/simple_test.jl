using MAT, LinearAlgebra, Statistics
include(ARGS[1]); using .blp
d = matread("/Users/erickom/Documents/GitHub/problem-set-io/code/build/input/public/simulation/10markets3products.mat")
J, T = size(d["P_opt"])
p = reshape(d["P_opt"], (T*J,1)); sh = reshape(d["shares"], (T*J,1))
m = blp.BLPDemand(BLPData=blp.BLPData(T, J, d["x1"], p, sh, log.(d["alphas"] .- 1)))
pb = blp.compute_hausman(m); Xr = blp.compute_blp(m)
m.Z = hcat(m.X, pb, Xr); m.W = inv(m.Z'*m.Z)
m.M = (I - m.X_all*inv(m.X_all'*m.Z*m.W*m.Z'*m.X_all)*m.X_all'*m.Z*m.W*m.Z')
f(s) = blp.gmm_fg!(0.0, nothing, m, s, toler=1e-13)
G = zeros(1); blp.gmm_fg!(nothing, G, m, 1.0, toler=1e-13)
println("analytic grad = ", G[1], "  finite diff = ", (f(1.0+1e-5)-f(1.0-1e-5))/2e-5)
t = @elapsed (for _ in 1:20; blp.contraction(m, 1.0, toler=1e-12); end)
println("20 contractions: ", round(t, digits=2), "s")
