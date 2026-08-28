function [return_flag]=generate_oi_sst(year,day,varargin);
%
% Original Producer: Andy Harris
% Editor: Momoe Yoshida, 2025-
%
% Program to generate NOAA Operational Analysis from GOES (Geostationary Operational Environmental Satellites)
% and POES (Polar Operational Environmental Satellites) SST data for the input date.
%
% use varargin to allow flexibility
%
% e.g., generate_oi_sst(2025,2), julian day

% ================================================================================================
% Name: generate_oi_sst.m
%
% Commenting system standard format (consistent, scalable and searchable):
%     [PRIORITY][TOPIC][PERSON][TYPE]: message
%     [PRIORITY]:
%           P1: High (urgent+important)
%           P2: Medium
%           P3: Low
%     [TOPIC]:
%           Ch1:
%           Ch2:
%           Ch3:
%           Ch4:
%           Oth: Others
%     [PERSON]:
%           ANDY:
%           SCOTT:
%           ME (MOMOE):
%     [TYPE]:
%           Q: Question
%           HYP: My hypothesis/guess
%           KEY: Important code logic
%           IDEA: New idea
%           TODO: Action needed
%     Example to search: /\[P1\].*\[ANDY\]
%                        /\[P1\].*\[ME\]\[Q\] 
% 
% History: 
%     Original version by Andy Harris 
%     Modified version here by Momoe Yoshida
%
% ================================================================================================


% Add MS directory (and all its subfolders) to MATLAB path
addpath(genpath(fullfile('..', 'MS')));

message2(['*** Generating OI SST for Day ' num2str(day) ' Year ' num2str(year)])

global file_info par_info return_flag

return_flag=1;

% Initialisation.
init_par_info;
init_file_info;

% [P3][Ch1][ANDY][Q]: 0/1 switch?
start_day_night = par_info.start_day_night;
end_day_night = par_info.end_day_night;

% Read the maximum and minimum values of SST from the "init_par_info.m".
% used at the very end (write_coastwatch_5km).
max_val=par_info.sst_analysis_max; %40.0
min_val=par_info.sst_analysis_min; %-2.0

bad_val=par_info.bad_val; %-999.
max_obs_deviation=par_info.max_obs_deviation; %3.0
correlation_min=par_info.correlation_min; %8.0
correlation_max=par_info.correlation_max; %32.0
correlation_scaling=par_info.correlation_scaling; %0.4

sst_variability_scaling=par_info.sst_variability_scaling; %0.5
sst_variability_min=par_info.sst_variability_min; %0.50
sst_variability_max=par_info.sst_variability_max; %3.00
sst_variability_weighting=par_info.sst_variability_weighting; %[0.8,0.2]
oi_corr_parm_001=par_info.oi_corr_parm_001; % [8,16,32]
oi_corr_parm_002=par_info.oi_corr_parm_002; %[200]
oi_corr_parm_003=par_info.oi_corr_parm_003; %[200]
oi_density=par_info.oi_density;%1
oi_nweight=par_info.oi_nweight;%0
oi_function_type=par_info.oi_function_type;%5
analysis_smoothing_factor=par_info.analysis_smoothing_factor;%4
error_smoothing_factor=par_info.error_smoothing_factor;%5
sst_analysis_min=par_info.sst_analysis_min;
sst_analysis_max=par_info.sst_analysis_max;
obs_variation_max=par_info.obs_variation_max;%6.0
error_val_max=par_info.error_val_max;%1
spatial_resolution=par_info.spatial_resolution;%[3600,7200]

% Use global file_info structure as defined by init_file_info.m to 
% determine information about directories and filename.

dir_analysis             = file_info.dir_analysis;
dir_input_ssts           = file_info.dir_input_ssts;
dir_ancillary           = file_info.dir_ancillary;
dir_coastwatch           = file_info.dir_coastwatch;

dir_ms_overlap           = file_info.dir_ms_overlap;
dir_ms_smoother          = file_info.dir_ms_smoother;
dir_ms_statecorr         = file_info.dir_ms_statecorr;
dir_ms_executable        = file_info.dir_ms_executable;

name_sst_analysis        = file_info.name_sst_analysis;
name_error_analysis      = file_info.name_error_analysis;
name_sst_variability     = file_info.name_sst_variability;
name_ice_mask            = file_info.name_ice_mask;
name_correlation_map     = file_info.name_correlation_map;
name_land_mask           = file_info.name_land_mask;
name_oi_oceans_coupling  = file_info.name_oi_oceans_coupling;
name_oi_state_values     = file_info.name_oi_state_values;
name_oi_scales           = file_info.name_oi_scales;
name_coastwatch_file     = file_info.name_coastwatch_file;

n_datasets               = file_info.var_n_datasets; % 10: nighttime only for CoralTemp
% [P2][Ch2][ME][Q]: What if I reduce file_info.var_n_datasets from 10?
%dataset_ids              = file_info.dataset_ids; % [1,2,3,4,5,6,7,8,10]

% Check processing direction to ensure the correct reference SST is used.
% Normally this is set to one, and the reference day is the day previous
% to the one in question. However if direction is -1, the day chronologically
% afterwards (i.e., the next day) is used. Other values may also be specified. For example, if 
% direction is set to 7, the reference biases from 7 days ago will be used.
% 
if (length(varargin) >0)
   direction=varargin{1}(1);
else
   direction=1; % default: the reference day = the previous day
end

% Determine string for date in yyyy_ddd format from input year and day of year,
% where yyyy is year, and ddd is day of year.
% For example, day 36 of year 2004 is specified with the string "2004_036".
% Also get string for previous day, as various datafiles from the previous day will
% be required.

date_string=get_datestring(year,day); %e.g., 2025_002
today=date_string;
day_before=get_datestring(year,day-direction); %e.g., 2025_001

yearstring=num2str_pad_zeros(year,4); %e.g., 2025
daystring=num2str_pad_zeros(day,3); %e.g., 002

yesterday=day_before;

% CREATE input_l3c_str (first part of obs_file; e.g., mtsat_) from the list (skip 001 ostia) 
input_l3c_str = ''; % Momoe
% FOR each number in the list (the list of numbers corresponding to input L3C data):
%for i=dataset_ids % Momoe
%   % Momoe *******
%   data_string=num2str_pad_zeros(i,3);
%   field_name = ['name_dataset_' data_string];
%   value = file_info.(field_name);
%   % Extract first part before 'night_'
%   parts = split(value, '_');
%   prefix = parts{1};   % e.g. 'METOPB'
%   input_l3c_str = [input_l3c_str prefix '_'];
%   % Momoe *******
%end

message2(['*** DEBUG001 '])
% Load up required data files from previous day, informing user as
% files are loaded.

message2(['*** Loading up data from previous day: ' yesterday])

eval(['load ' dir_analysis file_info.name_sst_analysis input_l3c_str yesterday ' sst_analysis']);
message2(['*** Loading ' dir_analysis name_sst_analysis input_l3c_str yesterday])

eval(['load ' dir_analysis file_info.name_sst_variability input_l3c_str yesterday ' sst_variability']);
message2(['*** Loading ' dir_analysis name_sst_variability input_l3c_str yesterday]);

%eval(['load ' dir_analysis file_info.name_correlation_map input_l3c_str yesterday ' correlation_map']);
%message2(['*** Loading ' dir_analysis name_correlation_map input_l3c_str yesterday ]);
% [P3][Oth][ANDY][Q]: obs_correlation_map of yesterday used anywhere in this code? 
% [P3][Oth][ANDY][HYP]: I don't think so, comment out for now.
%eval(['load ' dir_analysis file_info.name_obs_correlation_map yesterday ' obs_correlation_map']);
%message2(['*** Loading ' dir_analysis name_obs_correlation_map yesterday ]);

% [P1][Ch1][ME][Q]: How are ice_mask and land_mask used in this code?
eval(['load ' dir_analysis file_info.name_ice_mask today ' ice_mask']);
message2(['*** Loading ' dir_analysis name_ice_mask today]); 

message2(['*** Loading Landmask'])
eval(['load ' dir_ancillary file_info.name_land_mask ' land_mask ']);
message2(['*** Loading ' dir_ancillary name_land_mask]);


message2(['*** DEBUG002 '])
% Use ice and land masks to get vectors for ice and land positions.

land=find(land_mask==0);
ice=find(ice_mask==1);
land_or_ice=find(ice_mask>0);


% Modify daily SST variability for use in OI. 
% The mean absolute daily variation is stored and a scaled and constrained
% version is used by the OI to determine how much variability is 
% characteristic of tis location. However, this does NOT constrain the 
% estimated anomaly to be less than this value. 
%
% sst_variability_scaling = scaling factor: Typically 0.5.
% sst_variability_min    = minimum value allowed. 
% sst_variability_max    = maximum value allowed.

% [P1][ANDY/SCOTT/ME][Q]: what is sst_variability? how does it used? what does it do? key variable for my study?
% [P1][Ch1][ANDY][Q]: Why sst_variability_scaling=0.5?
sst_variability=sst_variability_scaling*sst_variability; % this sst_variability is what we loaded in line 114 (from the previous day's analysis)
sst_variability=min(sst_variability, sst_variability_max); % limit sst_variability to sst_variability_max
sst_variability=max(sst_variability, sst_variability_min); % ensure sst_variability to sst_variability_min at least
% sst_variability_min ≤ sst_variability ≤ sst_variability_max
% scaled version


% Load observational data

message2(['*** Loading Observational SSTs'])
message2(['*** DEBUG003 '])

obs_list='';
cov_list='';

% Initialize
full_obs=zeros(spatial_resolution); %[3600,7200]

% Momoe: if thinning is active.
   if isfield(par_info, 'thinning') && par_info.thinning == 1
        tr_value = par_info.thinning_ratio * 100; % avoid having '.' in filename
        tr_str = sprintf('tr%d_seed%d_', round(tr_value), par_info.seed_base);
   else
        tr_str = '';
   end

% Loop over each input satellite data, including both day and night.
% TNT Ch.2: I may adjust around here to thin data!
% n_datasets: from 10 > 9(remove jpss_night_c0) > 8(remove mtsat_night) > 7-4(no affect for GBR) > 3(remove METOPC_night_c0) > 2(remove METOPB_night_c0; max thinning)? & Add message2(['*** Thinning name_dataset-particular input data thinned'])?
% What if we want to only remove METOPB (#003) but keep using the others?
% • how many good/ok L3C SST values available in each pixel and which input satellite data?

% [P1][Ch1][ANDY][Q]: OSTIA is used as an input data? 
% [P1][Ch1][ANDY][HYP]: 1/4 degree,  only every 5th row and column is filled with real values from sst. The other entries remain whatever they were initialized with (NaN).

% FOR each number in the list (the list of numbers corresponding to input L3C data):
%for i=dataset_ids % Momoe

for i=1:n_datasets % thinned ostia: 001
    % n_datasets control the # of input satellite data
   % For each input satellite data.
   data_string=num2str_pad_zeros(i,3);
   
   message2(['*** DEBUG004 '])
   
   % Load up observational data.
   obs_file=['file_info.name_dataset_' data_string]; %e.g., viirs_night_c0_
   eval(['obs_file=' obs_file ';'])
   
   full_obs_filename=[ dir_input_ssts obs_file date_string '.mat'];

   % Check observational data are present. If not, insert empty dataset.

   sst=0.	%  Initialize SST 'array' to a scalar containing zero for testing (see below)

   fid=fopen(full_obs_filename);
   if(fid>0)   
      fclose(fid);
      eval(['load ' dir_input_ssts obs_file date_string ' sst stdvals gridcount bias']);
      message2(['*** Loading ' dir_input_ssts obs_file date_string]);
   end

   sst_size=size(sst);		%  Get the size of the input SST array.  Input file may still be created 
				%  by ingester even though raw data files are absent.  However, size of
				%  SST array will be [1 1] rather than (e.g.) [3600 7200]

   if(sst_size(1)*sst_size(2)==1)
      message2(['*** ' dir_input_ssts obs_file date_string ' not found; inserting empty dataset.'])
      sst=NaN*ones(spatial_resolution);
      stdvals=zeros(spatial_resolution);
      bias=zeros(spatial_resolution);
      eval(['save ' full_obs_filename ' sst stdvals bias']);
   end
   
   % Set minimum value for standard deviation.

   % Set minimum value (0.15) for standard deviation.
   % ANDY: Why 0.15?
   too_low=find(stdvals<0.15);
   stdvals(too_low)=0.15;
   clear too_low % remove the variable named too_low from the workspace
   if(0)
      % This code won't run
      only_one=find(gridcount==1);
      only_two=find(gridcount==2);
      stdvals(only_one)=0.5;
      stdvals(only_two)=0.4;
      % ANDY: Why 0.5 and 0.4? What's this code block for?
      clear only_one only_two
   end
   clear gridcount only_one only_two
   %pack         % old command that is now deprecated
   

   % ***20250702_MT/Andy***
   % An analysis system analyses anomalies. The difference between
   % observation and the inital guess (yesterday's SST). No model related
   % at all (simple assumption: today's SST would be very similar to
   % yesterday's SST).

   % Calculate anomalies (Delta SST from yesterday).
   % Update bias correction (Maturi et al. 2017–Fig1.process flowchart)
   obs=sst+bias-sst_analysis; % KEY
   % obs will be NaN if sst is NaN regardless of the values of sst_analysis
   % ANDY: sst and sst_analysis don't match in unit and scale???? in �C??
   % obs = L3 SST + L3 Bias - L4 SST (reference: previous day's
   % analysis)
   % how is the L3 Bias calculated (and SST)? (bias correction value) -> cmax (matlab executable)
   % L3: accumulated, constructed by injestion code -> /andy.harris/for_me/blended/blended_home/Software/
   % e.g., process_raw_goes_c.m call max functions (.c: efficient code) -> /andy.harris/for_me/blended/blended_home/C_code/c_code_andy5/
   % why the bias added -> apply the bias correction

   % bias: the estimated bias correction for that sensor at that, always 0 for ostia right(bias-free reference)?
   % time/location
   % sst_analysis: the background/reference/previous day's (yesterday's)
   % field/sst

   too_big=find(abs(obs)>max_obs_deviation); % >3.0, ANDY: large real changes may be rejected? cab introduce correlated biases?
   obs(too_big)=NaN;
   obs(land)=NaN;
   cov=stdvals.*stdvals;  % KEY
   % the diagonal elements of the covariance matrix, how much a set of numbers is spread out (how far each number in the set is from the mean (average) and how far the numbers are from each other)
   % stdvals from the input satellite data
   % square of stdvals
   
   % Quality Control–flagging.
   % Replace NaN with bad_val.
   bad=find(isnan(obs));
   obs(bad)=bad_val; % -999.
   cov(bad)=bad_val;
   bad=find(stdvals==0);
   obs(bad)=bad_val;
   cov(bad)=bad_val;

      
   % Assign the current values of obs and cov to the variables obs/cov_
   % (e.g., obs_001).
   eval(['obs_' data_string '=obs;'])
   eval(['cov_' data_string '=cov;'])
   
   obs_list=[obs_list 'obs_' data_string ','];
   cov_list=[cov_list 'cov_' data_string ','];
 
   ok=find(obs>bad_val); % KEY
   % TNT: add some codes here if we want to know which L3C SST (platform) is available?
   full_obs(ok)=1; % full_obs: a binary mask (1=valid obs and 0=no/bad data), overwrite every time
   % to know whether a 0.05ºx0.05º pixel had any valid observation from at least one satellite

                  message2(['*** DEBUG007'])
end % this for loop is all for creating obs_list and cov_list and full_obs, parameters for the function mult_groupb_new
   message2(['*** DEBUG019'])

clear cov bias obs sst stdvals global_sst global_stdvals 
% ANDY: global_sst and global_stdvals?


% Determine location of MultiScale (MS) estimation software.


% Now include these directories in the search path.
% User is advised which directories will be used from the init_file_info.m.

message2(['*** Adding path to ' dir_ms_overlap])
eval(['addpath ' dir_ms_overlap])

message2(['*** Adding path to ' dir_ms_smoother])
eval(['addpath ' dir_ms_smoother])

message2(['*** Adding path to ' dir_ms_statecorr])
eval(['addpath ' dir_ms_statecorr])

message2(['*** Adding path to ' dir_ms_executable])
eval(['addpath ' dir_ms_executable])

   message2(['*** DEBUG020'])

% Read in other parameters used by OI.
% User is informed of files being loaded.

message2(['*** Loading ' dir_ancillary name_oi_oceans_coupling ]);
eval(['load ' dir_ancillary name_oi_oceans_coupling ]); % [ME][Q] how does this data file look like? used for what? sth to do with ocean basin separation?
message2(['*** Loading ' dir_ancillary name_oi_state_values ]);
eval(['load ' dir_ancillary name_oi_state_values ]);
message2(['*** Loading ' dir_ancillary name_oi_scales ]);
eval(['load ' dir_ancillary name_oi_scales ]);
     
   message2(['*** DEBUG021'])


% Calculate estimates

n_fields = [1 2 2 1];

%size_n_datasets = numel(n_datasets) % Momoe 
measurement_model = ones(n_datasets,1); % create a column vector of size n_datasets × 1 where every entry is the number 1

% Set quantries scaling (expert level knowledge–Momoe may not need to know)
oi_scales=scales; % scales is the variable in the oi_scales file (../data/oi_scales.mat)
% 'scales': array([[  8, 128,  57,  66,  66,   1,   0, 128, 100,  56,  56, -27,   1]], dtype=int16)
% 8: level, 128: tile size–overlap, 57: 1/28 overlap rows and columns, -27: offset
% one direction
% full oi is very computationally expensive, n^3
% processing speed issue
   message2(['*** DEBUG022'])

% Loop over each correlation length.
for i=1:length(oi_corr_parm_001) % [8, 16, 32]

   message2(['*** DEBUG030'])
   istring=num2str_pad_zeros(i,3);

   % Call a function mult_groupb_new. what does this
   % function do and the input parameters (and meaning of numbers)
   % andy.harris/for_me/blended/blended_home/MS/Newcode/
   %comstring=['[anom,est_error] = mult_groupb( oi_scales, oi_density, n_fields,' ...
   comstring=['[anom,est_error] = mult_groupb_new( oi_scales, oi_density, n_fields,' ...
                 'oi_function_type, ss1, oi_corr_parm_001(i), sst_variability, oi_nweight,' ...
                 'measurement_model, ' obs_list  cov_list ' land_mask, oi_oceans_coupling, [1 ]);'] % KEY %TNT: overcome with errors here
   % oi_scales: array([[  8, 128,  57,  66,  66,   1,   0, 128, 100,  56,  56, -27,   1]], 
   % dtype=int16), a decomposition control vector
   % oi_density: 1
   % n_fields: [1 2 2 1], 
   % oi_function_type: 5
   % ss1?
   % oi_corr_parm_001: [8, 16, 32], the fixed correlation length used for that OI solve
   % sst_variability: yesterday's, prior variance field, used to define the background covariance model,
   % see line 145~, variability in that area recently to estimate how vary sst will be 
   % oi_nweight: 0
   % measurement_model: a column vector of size n_datasets(=19 -> 10) × 1 where every entry is the number 1
   % obs_list: multiple satellite observation deviations, a single long
   % character, the measurement values
   % cov_list: observation error covariance, controls how strongly observations influence the solution.
   % large/small error >>> weak/strong weight
   % string ('obs_001,obs_002,obs_003,...,obs_019,')? Aren't they values
   % assigned at line240?
   % oi_oceans_coupling: .mat file in data file
   % back in the 90s
   % mult_fields6_newest(): actual OI solver which calls ms_cc6_corr(), a
   % compiled MEX C routine, Compute OI at fixed correlation length

   message2(['*** DEBUG031'])
   eval(comstring)
   message2(['*** DEBUG032'])
   



   anom=remove_overlap(anom, oi_scales);
  
   est_error=remove_overlap(est_error, oi_scales);
 
   % Find unusually large anom, over water and not yet flagged as bad!?
   vbad_anom=find((abs(anom)> obs_variation_max) & (land_mask>0) & (anom~=bad_val)); % land: where land_mask==0
   vbad_error=find((est_error<0) & (land_mask>0) & (est_error~=bad_val));

     
   message2(['*** DEBUG034'])
  
   %corr_length=oi_corr_parm_001(i); not used anywhere else
 
   % Constrain analysis by dumping result if estimated anomaly is greater than user-specified value.

   if(length(vbad_anom)>0)
      anom(vbad_anom)=0;
      est_error(vbad_anom)=3;
   end
   message2(['*** DEBUG035'])
   
   anom(land)=NaN;
   est_error(land)=NaN;

   % Compute the numerical gradient of the anom (anomaly) field in both the x (longitude) and y (latitude) directions.
   % i.e., Return the partial derivatives of a 2D array.
   [fx,fy]=gradient(anom);
   extreme=find(abs(fx)>10 | abs(fy)>10);
   if(length(extreme)>0)
      anom(extreme)=0.0;
      est_error(extreme)=3.;
   end
   clear fx fy extreme

   message2(['*** DEBUG038'])
   % ANDY: what are they? (anom_ and error_)
   eval(['anom_' istring '=anom;'])
   eval(['error_' istring '=est_error;']) 
   clear anom est_error
 
   message2(['*** DEBUG039'])

end % this for loop is all for creating anom/error_00# (each produced with different assumed correlation lengths)

message2(['*** DEBUG040'])


% Interpolate according to appropriate correlation map.

init_sst_analysis=sst_analysis; % L4 SST (background/reference field: previous day's analysis)

message2(['*** DEBUG041'])

% Create correlation map from observation map (detailed explanation in the code).
% dense/sparse observation/data region → small/large correlation length (lmin/lmax)
% [3600,7200]; each grid cell gets a value between lmin and lmax
correlation_map=get_cmap(full_obs,8,32); % full_obs: a binary mask (1=valid obs and 0=no/bad data)
%correlation_map=get_cmap(full_obs,oi_corr_parm_001(1),oi_corr_parm_001(3)) % replace 8 and 32 with oi_corr_parm_001(1) and oi_corr_parm_001(3)? ANDY
% may be not � any particular purpose?
clear full_obs

% correlation_map: the correlation_map of yesterday line117
% these two lines below may not need because correlation_map should be
% already between 8 and 32? ANDY
% correlation_map=min(correlation_map,32);
% correlation_map=max(8,correlation_map);
correlation_map=min(correlation_map,32);
correlation_map=max(8,correlation_map);

message2(['*** DEBUG042'])


% SST Analysis is modified using correlation map of SST variability
% modified by data distribution.
% Error Analysis correlation map is based only on underlying SST variability.

%1-3: each correlation length [8, 16, 32], run the analysis 3 times
% Today's correlation_map
% corr_interp: correlation-weighted interpolation
% Are the spatial_resolution of obs_correlation_map and anom_ and eror_
% [3600,7200]? ANDY Momoe: i think so
% Interpolate between solutions pixel-by-pixel based on how close the local cmap 
% value is to each fixed length–Classic weighted interpolation. Use cmap to
% adaptively choose which OI solution to trust at each location–adaptive blending.
% anom_analysis: interpolated anomaly map (a solution weighted toward the most 
% appropriate correlation length), OI-estimated SST anomaly field (ªC)? ANDY KEY!
% the correction applied to the background SST (previous day's L4 SST)
% error_analysis:  interpolated error variance map (same as above)
% anom/error_XXX: OI solutions/estimate computed at fixed correlation
% lengths-correct? ANDY
[anom_analysis, error_analysis]=corr_interp( correlation_map, ...
                                     oi_corr_parm_001(1), anom_001, error_001, ...
                                     oi_corr_parm_001(2), anom_002, error_002, ...
                                     oi_corr_parm_001(3), anom_003, error_003); % KEY

% using Yesterday's correlation_map, used anywhere?
% [anom_analysis_1, error_analysis_1]=corr_interp( correlation_map, ...
%                                      oi_corr_parm_001(1), anom_001, error_001, ...
%                                      oi_corr_parm_001(2), anom_002, error_002, ...
%                                      oi_corr_parm_001(3), anom_003, error_003); 

message2(['*** DEBUG043'])


% Smooth analysis using smoothing factors set in init_par_info.
%  Call a function smooth_analysis.
% andy.harris/for_me/blended/blended_home/Software/
% error_smoothing_factor: 5
smooth_error_analysis=smooth_analysis(error_analysis,error_smoothing_factor);

good=find(~isnan(anom_analysis) & ~isnan(error_analysis));
unsmoothed_sst_analysis=0*init_sst_analysis; % the same size and type as init_sst_analysis filled with zeros
% KEY
unsmoothed_sst_analysis(good)=anom_analysis(good)+init_sst_analysis(good); % init_sst_analysis: previous day's L4 SST
unsmoothed_sst_analysis(land)=bad_val;
error_analysis(land)=bad_val;

message2(['*** DEBUG044'])

% analysis_smoothing_factor=4, ANDY why even number rather than odd (to get exact centre)?
sst_analysis=smooth_analysis(unsmoothed_sst_analysis,analysis_smoothing_factor);
good=find(~isnan(sst_analysis) & ~isnan(smooth_error_analysis));

% Constrain temperature of SST Analysis to user-specified range,
% typically -1.8 - 35.0 deg C. 
% val_min_sst_analysis & val_max_sst_analysis can be changed
% in init_par_info.m

bad=find(sst_analysis==bad_val | isnan(sst_analysis));
sst_analysis=min(sst_analysis, sst_analysis_max);
sst_analysis=max(sst_analysis, sst_analysis_min);
sst_analysis(bad)=bad_val;


% Set negative error values to bad value.

smooth_error_analysis(find(smooth_error_analysis<0))=error_val_max;
smooth_error_analysis=sqrt(smooth_error_analysis);
smooth_error_analysis(isnan(smooth_error_analysis))=bad_val;

message2(['*** DEBUG050'])

error_analysis=smooth_error_analysis;

% Modify SST Variability.
% 0.8*yesterday's variability + 0.2*today's anom + today's analysis error
sst_variability(good)=sst_variability_weighting(1)*sst_variability(good) + ...
                      sst_variability_weighting(2)*abs(anom_analysis(good))+ ...
                      sqrt(error_analysis(good));

% Modify correlation map if required.

mod_correlation_map=0;
if(mod_correlation_map) % if 0 >>> the code block within that if statement will never execute
    % Calculate gradient of sst_analysis. gradient strength
   [gradx,grady]=gradient(sst_analysis);
   grad=sqrt(gradx.*gradx+grady.*grady);
   invert_gradient=1./grad;
   correlation_map=invert_gradient*correlation_scaling; 
   correlation_map(land)=correlation_max;
   correlation_map=min(correlation_map, correlation_max);
   correlation_map=max(correlation_map, correlation_min);
   correlation_map=smooth_fill(correlation_map,land_mask,7);
   correlation_map=min(correlation_map, correlation_max);
   correlation_map=max(correlation_map, correlation_min);
end

message2(['*** DEBUG050'])
% Update and save SST Analysis

message2(['*** Writing results to ' dir_analysis])

eval(['save ' dir_analysis name_sst_analysis tr_str input_l3c_str date_string ' *sst_analysis file_info']); % save any variable ending in sst_analysis and file_info, CoralTemp
eval(['save ' dir_analysis name_error_analysis tr_str input_l3c_str date_string ' error_analysis']);
eval(['save ' dir_analysis name_sst_variability tr_str input_l3c_str date_string ' sst_variability']);
% eval(['save ' dir_analysis name_correlation_map tr_str date_string ' correlation_map' ]); % yesterday's
eval(['save ' dir_analysis name_correlation_map tr_str input_l3c_str date_string ' correlation_map' ]); % today's

message2(['*** DEBUG060'])

% Write coastwatch file

% processing_date=date;
% filename=[dir_coastwatch name_coastwatch_file date_string '.hdf'];
% five_or_eleven_km='5km_';
% filename=[dir_coastwatch name_coastwatch_file five_or_eleven_km yearstring daystring '.hdf'];
%message2(['*** Writing Coastwatch file ' filename])
% ok=write_coastwatch_5km(filename, year, day, sst_analysis, error_analysis, ...
%                    land_mask, ice_mask, processing_date, bad_val, max_val, min_val );
		    
message2(['*** DEBUG070'])

% Write GHRSST L4 GSD 2.0 netCDF and metadata files
%%% Note: Landmask and ice mask loaded within write_ghrsst_gds2

%if (start_day_night == 0) & (end_day_night == 1)
 % message2(['*** Writing GHRSST L4 DAY/NIGHT files for day and year' num2str(day), num2str(year) ])
  %ok=write_ghrsst_gds2_day_night(year, day, sst_analysis, error_analysis);
%elseif (start_day_night == 1) & (end_day_night == 1)
 % message2(['*** Writing GHRSST L4 NIGHT ONLY files for day and year' num2str(day), num2str(year) ])
  %ok=write_ghrsst_gds2_night_only(year, day, sst_analysis, error_analysis);
%end

return_flag=1;
