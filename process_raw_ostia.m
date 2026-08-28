function [ok]= process_raw_ostia(year, day, res);

% Program to process OSTIA data (1/20 degree)

global file_info par_info return_flag
global yesterday

init_par_info;
init_file_info;

dir_input_ssts=file_info.dir_input_ssts;
dir_analysis=file_info.dir_analysis;
dir_ancillary=file_info.dir_ancillary;
name_sst_biases=file_info.name_sst_biases;
name_land_mask=file_info.name_land_mask;
spatial_resolution=par_info.spatial_resolution;
tenth_or_twentieth=par_info.tenth_or_twentieth;

% Get thresholds from init_par_info file to be used for SST check.
% These are used to set climate threshold used for processing, eg:
%
%     Threshold =  noaa17_day_c0_threshold_mult*sst_variability + noaa17_day_c0_threshold_constant

std_threshold=par_info.std_threshold;

abs_zero=par_info.abs_zero;

sst_analysis_min=par_info.sst_analysis_min;
rtg_fac         =par_info.rtg_fac  
sst_min=sst_analysis_min-2;

% Assign file and parameter information to variable names.
dir_rtg_lowres  = file_info.dir_rtg_lowres; 
dir_rtg_hires   = file_info.dir_rtg_hires;
dir_rtg_lowres  = file_info.dir_rtg_lowres;
dir_rtg_hires   = file_info.dir_rtg_hires;
dir_ms_read_grib = file_info.dir_ms_read_grib;
name_rtg_lowres = file_info.name_rtg_lowres;        
name_rtg_hires  = file_info.name_rtg_hires; 
    

sst=-1;
landmask=-1;

% Get the 0.1x0.1 degree land mask

message2(['*** Loading Landmask' dir_ancillary name_land_mask])
eval(['load ' dir_ancillary name_land_mask ' land_mask ']);
message2(['*** Loaded ' dir_ancillary name_land_mask]);
land=find(land_mask<1);

datalabel = 'ostia_';

dir_ostia  = file_info.dir_ostia; 
name_ostia = file_info.name_ostia;        

mjd=date2mjd(year,day);
[year, dayinmonth, month]=mjd2date(mjd);

datestring=[num2str(year) num2str_pad_zeros(month,2) ...
            num2str_pad_zeros(dayinmonth,2)];


netcdf_file=[dir_ostia datestring name_ostia];

% Make sure it's there...

sstfiles=dir(netcdf_file);
nfiles=length(sstfiles);

message2(['*** Found ' num2str(nfiles) ' files for ' netcdf_file]);

% Warn user if no files found.

if(nfiles==0)
   message2(['*** Could not find ' netcdf_file '.'])
   message2(['*** No files found for OSTIA for '...
         num2str(year) ', day ' num2str(day) '. '])
   message2(['*** Check appropriate directory has been defined in init_file_info.'])
   ok=0;
   return
end

%nfiles=1;

% Set up geographical grids at 0.1deg spatial resolution to store SSTs
% and associated information. Each individual input file contributes a 
% maximum of one SST to every cell. Up to nmax values can be stored for one 
% day. 

nmax=1;
allvals=NaN*ones(spatial_resolution);
bias=zeros(spatial_resolution);     % Always zero for OSTIA data...

% Get the data...

[sst, land, ice] = get_ostia_netcdf(year, day);

% Make it double & set land to NaN...

sst2=double(sst);
sst2(land)=NaN;
sst=sst2';
clear sst2;

% Save full resolution OSTIA in Analysis directory for comparison...

message2(['*** Saving OSTIA file for ' num2str(year) ', day ' num2str(day)]);

eval(['save ' dir_analysis datalabel tenth_or_twentieth ...
       num2str_pad_zeros(year,4) '_' num2str_pad_zeros(day,3) ...
          ' sst']);

% Also take OSTIA ice mask because of gaps in NCEP archive

datalabel = 'ice_mask_';

ice_mask=zeros(spatial_resolution);
ice2=ice_mask';		% OSTIA ice & land indices are for 7200x3600 array (Matlab default is 3600x7200)
ice2(ice)=1.0;
ice2(land)=2.0;
ice_mask=ice2';		% Transpose back to 3600x7200
clear ice2;

% Save Ice in Analysis directory for comparison...

message2(['*** Saving OSTIA Ice Mask for ' num2str(year) ', day ' num2str(day)]);

eval(['save ' dir_analysis datalabel ...
       num2str_pad_zeros(year,4) '_' num2str_pad_zeros(day,3) ...
          ' ice_mask']);


% Subsample if needed...
% only every 5th row and column is filled with real values from sst-the other entries remain NaNs
thin=5;			% ...OSTIA is 1/20 degree so subsampling 1 in 5 gives 1/4 degree (same as for RTG_HR)

allvals(1:thin:end,1:thin:end)=sst(1:thin:end,1:thin:end);

% Update other required grids

gridcount=~isnan(allvals);      % Actually does exactly what we want...
stdvals=gridcount.*0.5;         % currently set 0.5 K accuracy for OSTIA, where valid SST is available(every 5th row and column by thinning above) and 0 at missing SST pixels...

sst=allvals;
      
% Where no quality control has been done output datafiles are prefixed with "raw_"

%     if(sst_check)
        check_label='';     % We don't check OSTIA but it doesn't matter...
%     else
%        check_label='raw_';
%     end

% Save data in "input_ssts" directory.

datalabel = 'ostia_';

     eval(['save ' dir_input_ssts check_label  datalabel ...
            num2str_pad_zeros(year,4) '_' num2str_pad_zeros(day,3) ...
          ' sst gridcount ' ...
          ' stdvals bias']);

     
clear sst gridcount stdvals allvals ice land
