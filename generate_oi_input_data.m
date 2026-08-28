function [return_flag]=generate_oi_input_data(year,day,stream,varargin);
% e.g., generate_oi_input_data(2025,011,'mio');
% Program to generate input data files from Operational SSTs for use in
% NOAA Operational Analysis from GOES
% and POES SST data.
%
% added a stream variable, if stream = goes, then goes only
% if stream = poes, then poes only


message2(['*** Generating output data for Day ' num2str(day) ' Year ' num2str(year)])

global file_info par_info return_flag;
global yesterday;
global logfile_fid;

return_flag=1;


% Get information about file locations and names and parameters.

init_file_info;
init_par_info;

% Assign file and parameter information to variable names.

sst_variability_scaling=par_info.sst_variability_scaling;
sst_variability_min=par_info.sst_variability_min;
sst_variability_max=par_info.sst_variability_max;
sst_variability_weighting=par_info.sst_variability_weighting;
spatial_resolution=par_info.spatial_resolution;

% Use global file_info structure as defined by init_file_info.m to 
% determine information about directories and filename.

dir_analysis             = file_info.dir_analysis;
dir_input_ssts           = file_info.dir_input_ssts;

name_sst_analysis        = file_info.name_sst_analysis;
name_error_analysis      = file_info.name_error_analysis;
name_sst_variability     = file_info.name_sst_variability;
%dataset_ids              = file_info.dataset_ids; % [1,2,3,4,5,6,7,8,9,10] %Momoe

% Check processing direction to ensure the correct reference SST is used.
% Normally this is set to one, and the reference day is the day previous
% to the one in question. However if direction is -1, the day chronologically
% afterwards is used. Other values may also be specified. For example, if 
% direction is set to 7, the reference biases from 7 days ago will be used.
% 

if (length(varargin) >0)
   direction=varargin{1}(1);
else
   direction=1;
end


% Determine string for date in yyyy_ddd format from input year and day of year,
% where yyyy is year, and ddd is day of year.
% For example, day 36 of year 2004 is specified with the string "2004_036".
% Also get string for previous day, as various datafiles from the previous day will
% be required.

date=get_datestring(year,day);
yesterday=get_datestring(year,day-direction);


% Default action is to quality control input SST data with respect to reference SST dataset
% (usually previous day's estimate, but this quality control will be omitted if sst_check is
% set to 0 as fourth argument in calling function.

if (length(varargin) >1)
   sst_check=varargin{2}(1);
else
   sst_check=1; % default
end

% CREATE input_l3c_str (first part of obs_file; e.g., mtsat_) from the list (skip 001 ostia) 
input_l3c_str = ''; % Momoe
% FOR each number in the list (the list of numbers corresponding to input L3C data):
%message2(['*** dataset_ids: ' dataset_ids])
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
% ANDY: any C codes I need to modify due to this change?

message2(['*** DEBUG001 '])
%message2(['*** input_l3c_str: ' input_l3c_str])

% If quality control is to be performed, then load up reference data set.
message2(['*** sst_check: ' sst_check])
if(sst_check)

% Load up required reference data files (usually from previous day, OSTIA), informing user as
% files are loaded.

   message2(['*** Loading up data from previous time step: ' yesterday])

   eval(['load ' dir_analysis file_info.name_sst_analysis input_l3c_str yesterday ' sst_analysis']); % Momoe
   message2(['*** Loading ' dir_analysis name_sst_analysis input_l3c_str yesterday])


   eval(['load ' dir_analysis file_info.name_error_analysis input_l3c_str yesterday]);
   message2(['*** Loading ' dir_analysis name_error_analysis input_l3c_str yesterday]);


   eval(['load ' dir_analysis file_info.name_sst_variability input_l3c_str yesterday]);
   message2(['*** Loading ' dir_analysis name_sst_variability input_l3c_str yesterday]);


% Modify daily SST variability for use in OI. 
% The mean absolute daily variation is stored and a scaled and constrained
% version is used by the OI to determine how much variability is 
% characteristic of tis location. However, this does NOT constrain the 
% estimated anomaly to be less than this value. 
%


   sst_variability=sst_variability_scaling*sst_variability;
   sst_variability=min(sst_variability, sst_variability_max);
   sst_variability=max(sst_variability, sst_variability_min);


% Use rtg for climatology  
% analysis_2004001.dat  error_2004001.dat variability_20004001.dat
% bias fields

else

% Create dummy reference SST and very large SST variability if no quality control
% required. 

   sst_analysis=zeros(spatial_resolution);
   sst_variability=1000*ones(spatial_resolution);

end

% Set reference sst to sst_analysis

%
% For testing of new bias correction, just ingest 'slstr', 'goes', 'poes', 'jpss', 'metopc' and 'ostia' ('thinned' OSTIA is needed for the AMSR)
% In the actual analysis, only N20, MetOp-B&C and GOES-16 are analyzed to speed things up for testing/demonstration
%

ref_sst=sst_analysis; % previous day's analysed L4 SST

% Process geostationary, polar-orbiting and RTG data

if (strcmpi(stream,'goes') || strcmpi(stream,'all')) % GOES-East/West, TNT: download the correct L2P data files from website and save into blended_home/Data/goes
	process_raw_goes_c(stream, year, day, ref_sst, sst_variability, sst_check);
end

% Use when there's MSG (Meteosat Second Generation) & MTSAT (Multifunctional Transport Satellite, i.e., Himawari) available
if (strcmpi(stream,'msg') || strcmpi(stream,'all'))
        process_raw_msg_c(stream, year, day, ref_sst, sst_variability, sst_check);
end

% Use when there's MSG available over the Indian Ocean
if (strcmpi(stream,'mio') || strcmpi(stream,'all')) % Meteosat/MSG Indian Ocean
        process_raw_mio_c(stream, year, day, ref_sst, sst_variability, sst_check);
end

% Use when there's no MTSAT
%if (strcmpi(stream,'msg') || strcmpi(stream,'all'))
%        process_raw_msg_only_c(stream, year, day, ref_sst, sst_variability, sst_check);
%end

% Use when there's no MSG
%if (strcmpi(stream,'mtsat') || strcmpi(stream,'all'))
%        process_raw_mtsat_only_c(stream, year, day, ref_sst, sst_variability, sst_check);
%end

% Use when there is no MTSAT but there is GOES-9 (1995-2007) in W Pac.
%if (strcmpi(stream,'msg') || strcmpi(stream,'all'))
%        process_raw_goesp_c(stream, year, day, ref_sst, sst_variability, sst_check);
%end

if (strcmpi(stream,'poes') || strcmpi(stream,'all')) % viirs and METOPB
	process_raw_avhrr_acspo_c(stream, year, day, ref_sst, sst_variability, sst_check);
end

%  JPSS is currently an 'additional' polar stream
if (strcmpi(stream,'jpss') || strcmpi(stream,'all'))
	process_raw_jpss_acspo_c(stream, year, day, ref_sst, sst_variability, sst_check);
end

% Jun-2025--------------------------------------------------------------------------------
%  MetOp-C is currently another 'additional' polar stream
if (strcmpi(stream,'metopc') || strcmpi(stream,'all'))
	process_raw_metopc_acspo_c(stream, year, day, ref_sst, sst_variability, sst_check);
end
% 
% %  Let's pull the SLSTR data.  This will be used as the bias correction reference
% if (strcmpi(stream,'slstr') || strcmpi(stream,'all'))
% 	process_raw_slstr_c(stream, year, day, ref_sst, sst_variability, sst_check);
% end
% 
% %  Let's pull the in situ data.  This will be used as a bias correction reference
% if (strcmpi(stream,'insitu') || strcmpi(stream,'all'))
% 	process_raw_insitu(stream, year, day, ref_sst, sst_variability, sst_check);
% end
% Jun-2025--------------------------------------------------------------------------------


if (strcmpi(stream,'ostia') || strcmpi(stream,'all'))
	res=1;
	thin=5;
%	process_raw_rtg(year, day, res, thin);
	process_raw_ostia(year, day, res); % what is ostia_2025_011.mat used for?? > input data for generate_oi_sst.m; thinned (e.g.,thin=5) ostia data
end

%if (strcmpi(stream,'amsr') || strcmpi(stream,'all'))
%	process_raw_amsr_c(stream, year, day, ref_sst, sst_variability, sst_check);
%end

% Set return flag to one on successful completion.

return_flag=1;

%
%  Create today's ice mask from NCEP ice concentration
%  ** process_raw_ostia() now used for ice mask as well because NCEP archive is incomplete **

%res=1;
%process_raw_ice(year, day, res);

