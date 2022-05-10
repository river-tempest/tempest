# Tempest

Tempest is a river TEMPerature ESTimation model implemented in R; it supports high-accuracy estimation of river temperatures using only satellite-based remote sensing data.  It has been validated for publicly-available datasets covering the continguous United States, but should be generalizable to other regions and datasets.  Detailed performance information is available in Philippus, D., Sytsma, A., Rust, A., and Hogue, T.S. (not yet submitted for review); briefly, median validation Root Mean Square Error is about 1.6-2 K for individual predictions, and errors are normally distributed within roughly plus or minus 4.5 K with bias of approximately 0.  Therefore, the model is suitable for statistical analyses of many locations, but should not be used for individual points or reaches without validation data.

Note that the model is provided with ABSOLUTELY NO WARRANTY regarding its accuracy or anything else.  The above performance information is typical behavior, not a guarantee.

# Usage

The model can be trained and tested on any CSV dataset; in most cases, column names are irrelevant, and it will simply use all columns that are provided with a few exceptions.  By default (but easily changed in the code), the output column in the training data should be called `temperature`, and a few named columns will be dropped.  Otherwise the only constraint is that the training and prediction datasets should have the same column names.  Default calibration and validation datasets, covering CONUS stream temperatures based on USGS gages, are provided.  By default the prediction function will simply predict median temperatures, but the `what` argument can be used to specify quantiles to predict, e.g. to estimate confidence intervals.  Full documentation is provided in Philippus et al. 2022.

# Data Collection

For the default setup, we provide a [Google Earth Engine script](https://code.earthengine.google.com/?accept_repo=users/dphilippus_mines/RST) (relevant file: runner.js) which will retrieve data in a suitable format for specified points and time intervals.  The GEE script is provided under the same terms, except that it builds on open-sourcecode from Ermida et al. (2020), which should also be credited and cited in any research using it.  Full citation information for Ermida et al. is provided in the comments in runner.js.

# License

This model is provided under the terms of the GNU General Public License v3.0.  It comes with absolutely no warranty, and you are free to use, modify, and redistribute it as long as any derivatives are provided under the same terms and credit is given.  By using this model or any data derived from it for research, you agree to cite the above-mentioned paper (Philippus et al. 2022).
