## Developer Cloud Sandbox for Sentinel-2 Atmospheric Correction using SEN2COR


This processing services applies the SEN2COR atmospheric correction to Sentinel-2 Level 1C tiles. The inputs are thus Sentinel-2 products containing Top of Atmosphere reflectances (TOA) and the outputs are Sentinel-2 products containing the tiles covering the area of interest and containing Bottom of Atmosphere reflectances (BOA).

SEN2COR is a prototype processor for Sentinel-2 Level 2A product formatting and processing. The processor performs the tasks of atmospheric-, terrain and cirrus correction and a scene classification of Level 1C input data. 

Sentinel-2 Level 2A outputs are:

* Bottom-Of-Atmosphere (BOA)
* optionally terrain- and cirrus corrected reflectance images
* Aerosol Optical Thickness
* Water Vapour
* Scene Classification maps and Quality Indicators, including cloud and snow probabilities.

## Quick link
 
* [Getting Started](#getting-started)
* [Installation](#installation)
* [Submitting the workflow](#submit)
* [Community and Documentation](#community)
* [Authors](#authors)
* [Questions, bugs, and suggestions](#questions)
* [License](#license)
* [Funding](#funding)

### <a name="getting-started"></a>Getting Started 

To run this application you will need a Developer Cloud Sandbox that can be either requested at support (at) terradue.com

A Developer Cloud Sandbox provides Earth Sciences data access services, and helper tools for a user to implement, test and validate a scalable data processing application. It offers a dedicated virtual machine and a Cloud Computing environment.
The virtual machine runs in two different lifecycle modes: Sandbox mode and Cluster mode. 
Used in Sandbox mode (single virtual machine), it supports cluster simulation and user assistance functions in building the distributed application.
Used in Cluster mode (a set of master and slave nodes), it supports the deployment and execution of the application with the power of distributed computing for data processing over large datasets (leveraging the Hadoop Streaming MapReduce technology). 

### <a name="installation"></a>Installation

#### Pre-requisites

**Installing miniconda**

miniconda is a free Python distribution that includes a minimal set of Python packages.

To install miniconda, run the simple step below on the Developer Cloud Sandbox shell:

```bash
sudo yum install -y miniconda-3.8.3
```

**Installing SEN2COR conda package and dependencies** 

Conda is a cross-platform package manager and environment manager program that installs, runs, and updates packages and their dependencies. 
It is included in miniconda installed in the previous step.

To install SEN2COR conda package, run the simple step below on the Developer Cloud Sandbox shell:

```bash
sudo conda install -y sen2cor
```

Finally install openjpeg

```bash
sudo yum install -y openjpeg2
```

##### Using the releases

Log on the Developer Cloud Sandbox.

Download the rpm package from https://github.com/ec-ecopotential/dcs-sen2cor/releases.

Install the downloaded package by running these commands in a shell:

```bash
sudo yum -y install dcs-sen2cor-<version>.x86_64.rpm
```

> At this stage there are no releases yet due to a known limitations in SEN2COR described [here](http://forum.step.esa.int/t/sen2cor-writes-files-in-the-installation-folder-at-runtime/2013)

#### Using the development version

Install the pre-requisites as instructed above.

Log on the Developer Cloud Sandbox and run these commands in a shell:

```bash
git clone git@github.com:ec-ecopotential/dcs-sen2cor.git
cd dcs-sen2cor
mvn install
```

### <a name="submit"></a>Submitting the workflow

To submit the application with its default parameters, run the command below in the Developer Cloud Sandbox shell:

```bash
ciop-run
```
Or invoke the Web Processing Service via the Sandbox dashboard providing:

* The bounding box of the Area of Interest
* The start and end date/time of the Time of Interest
* The target resolution for Sentinel-2 Level-2A product in meters (10, 20 or 60)

### <a name="community"></a>Community and Documentation

To learn more and find information go to 

* [Developer Cloud Sandbox](http://docs.terradue.com/developer) 
* [SEN2COR FTP](http://s2tbx.telespazio-vega.de/sen2cor/)
* [SEN2COR forum](http://forum.step.esa.int/t/sen2cor-tool/468)

### <a name="authors"></a>Authors (alphabetically)

* Brito Fabrice
* Rossi Cesare

### <a name="questions"></a>Questions, bugs, and suggestions

Please file any bugs or questions as [issues](https://github.com/ec-ecopotential/dcs-sen2cor/issues/new) or send in a pull request if you corrected any.

### <a name="license"></a>License

Copyright 2016 Terradue Srl

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0

### <a name="funding"></a>Funding

The ECOPOTENTIAL project has received funding from the European Union's Horizon 2020 research and innovation programme under grant agreement No 641762
