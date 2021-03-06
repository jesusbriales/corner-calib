% Script to test cube noise

% Add necessary toolboxes
addpath('/home/jesus/Dropbox/Computer_Vision/Matlab_tests/VisionBase');
addpath(genpath('/home/jesus/Dropbox/Computer_Vision/Matlab_tests/PeterKoversi'));
cd /home/jesus/Code/Corner_Calibration
addpath(genpath(pwd))

test = COdometryTest(false); test.WITH_DEBUG = false;
test.Cam.sd = 0;

arr_x = 0.001:0.001:0.01;
Nsim = 1e4;

test.test( 'cube_sd', arr_x, Nsim );
