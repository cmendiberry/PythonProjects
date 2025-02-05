
-- Selection result as HTML

SET NOCOUNT ON
DECLARE @Rcount int;
SET @Rcount=0;
--Declare Variables to hold result set of each SQL Queries
DECLARE @html nvarchar(max),@html1 nvarchar(max),@html2 nvarchar(max),@html3 nvarchar(max),@html4 nvarchar(max),@html5 nvarchar(max),@html6 nvarchar(max),@html7 nvarchar(max),
        @html8 nvarchar(max),@html9 nvarchar(max),@html10 nvarchar(max),@html11 nvarchar(max),@html12 nvarchar(max),@html13 nvarchar(max),@html14 nvarchar(max),@html15 nvarchar(max),
		@html16 nvarchar(max),@html17 nvarchar(max),@html18 nvarchar(max),@html19 nvarchar(max),@html20 nvarchar(max),@html21 nvarchar(max),@html22 nvarchar(max),@html23 nvarchar(max),
		@html24 nvarchar(max),@html25 nvarchar(max),@html26 nvarchar(max),@html27 nvarchar(max),@html28 nvarchar(max),@html29 nvarchar(max),@html30 nvarchar(max),@html31 nvarchar(max);
DECLARE @header nvarchar(max),@header0 nvarchar(max), @header1 nvarchar(max),@header2 nvarchar(max),@header3 nvarchar(max),@header4 nvarchar(max),@header5 nvarchar(max),@header6 nvarchar(max),@header7 nvarchar(max),
        @header8 nvarchar(max), @header9 nvarchar(max),@header10 nvarchar(max),@header11 nvarchar(max),@header12 nvarchar(max),@header13 nvarchar(max),@header14 nvarchar(max),@header15 nvarchar(max),
		@header16 nvarchar(max), @header17 nvarchar(max),@header18 nvarchar(max),@header19 nvarchar(max),@header20 nvarchar(max),@header21 nvarchar(max),@header22 nvarchar(max),@header23 nvarchar(max),
		@header24 nvarchar(max), @header25 nvarchar(max),@header26 nvarchar(max),@header27 nvarchar(max),@header28 nvarchar(max),@header29 nvarchar(max),@header30 nvarchar(max),@header31 nvarchar(max);
DECLARE @Table1 nvarchar(max),@Table2 nvarchar(max),@Table3 nvarchar(max),@Table4 nvarchar(max),@Table5 nvarchar(max),@Table6 nvarchar(max),@Table7 nvarchar(max),
        @Table8 nvarchar(max),@Table9 nvarchar(max),@Table10 nvarchar(max),@Table11 nvarchar(max),@Table12 nvarchar(max),@Table13 nvarchar(max),@Table14 nvarchar(max),
		@Table15 nvarchar(max),@Table16 nvarchar(max),@Table17 nvarchar(max),@Table18 nvarchar(max),@Table19 nvarchar(max),@Table20 nvarchar(max),@Table21 nvarchar(max),
		@Table22 nvarchar(max),@Table23 nvarchar(max),@Table24 nvarchar(max),@Table25 nvarchar(max),@Table26 nvarchar(max),@Table27 nvarchar(max),@Table28 nvarchar(max),@Table29 nvarchar(max),@Table30 nvarchar(max),@Table31 nvarchar(max);
DECLARE @Result1 nvarchar(max),@Result2 nvarchar(max),@Result3 nvarchar(max),@Result4 nvarchar(max),@Result5 nvarchar(max),@Result6 nvarchar(max),@Result7 nvarchar(max),
        @Result8 nvarchar(max),@Result9 nvarchar(max),@Result10 nvarchar(max),@Result11 nvarchar(max),@Result12 nvarchar(max),@Result13 nvarchar(max),@Result14 nvarchar(max),
		@Result15 nvarchar(max),@Result16 nvarchar(max),@Result17 nvarchar(max),@Result18 nvarchar(max),@Result19 nvarchar(max),@Result20 nvarchar(max),@Result21 nvarchar(max),
		@Result22 nvarchar(max),@Result23 nvarchar(max),@Result24 nvarchar(max),@Result25 nvarchar(max),@Result26 nvarchar(max),@Result27 nvarchar(max),@Result28 nvarchar(max),@Result29 nvarchar(max),@Result30 nvarchar(max),@Result31 nvarchar(max);

-- Set Header Variable with Toc

SET @header =
N'<html><head><meta http-equiv="Content-Type" content="text/html; charset=US-ASCII">'+
N'<meta name="generator" content="TSQL">'+
N'<style> body {font:10pt Arial,Helvetica,sans-serif; color:black; background:White;} p {font:10pt Arial,Helvetica,sans-serif; color:black; background:White;} table,tr,td {font:10pt Arial,Helvetica,sans-serif; color:Black; background:#f7f7e7; padding:0px 0px 0px 0px; margin:0px 0px 0px 0px;} th {font:bold 10pt Arial,Helvetica,sans-serif; color:#336699; background:#	; padding:0px 0px 0px 0px;} h1 {font:16pt Arial,Helvetica,Geneva,sans-serif; color:#336699; background-color:White; border-bottom:1px solid #cccc99; margin-top:0pt; margin-bottom:0pt; padding:0px 0px 0px 0px;-'+
N'} h2 {font:bold 10pt Arial,Helvetica,Geneva,sans-serif; color:#336699; background-color:White; margin-top:4pt; margin-bottom:0pt;} a {font:9pt Arial,Helvetica,sans-serif; color:#663300; background:#ffffff; margin-top:0pt; margin-bottom:0pt; vertical-align:top;}</style>'+
N'<title>SQL Server Support Bundle </title></head>' + CHAR(10) +
N'<body style="font-family: Arial">' +
N'<h1 align="center">DMS SQL Server Support Bundle</h1>'+
N'<div >'+
N'<p><strong>Contents</strong></p>'+
N'<ol>'+
N'<li><a href="#Overview">Overview</a>'+
N'<li><a href="#DatabaseConfiguration">SQLServer Configuration</a>'+
N'<ol>'+
N'<li><a href="#DatabaseConfiguration1">SQLServer Version</a></li>'+
N'<li><a href="#DatabaseConfiguration2">MS Replication Distributor</a></li>'+
N'<li><a href="#DatabaseConfiguration3">AlwayOn Configuration</a></li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#DatabaseDetails">Database Details</a>'+
N'<ol>'+
N'<li><a href="#DatabaseDetails1">Database Size</a></li>'+
N'<li><a href="#DatabaseDetails2">Database Recovery Model</a></li>'+
N'<li><a href="#DatabaseDetails3">Replication Property</a></li>'+
N'<li><a href="#DatabaseDetails4">Associated CodePage</a></li>'+
N'<li><a href="#DatabaseDetails5">Is RDS Database?</a></li>'+
N'<li><a href="#DatabaseDetails6">Database Encryption</a></li>'+

N'</ol>'+
N'</li>'+
N'<li><a href="#Permissions">Permissions</a>'+
N'<ol>'+
N'<li><a href="#ServerPermissions">Server Level</a></li>'+
N'<li><a href="#DatabasePermissions">Database Level</a></li>'+
N'<li><a href="#SysadminPermissions">Is SysAdmin?</a></li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#DatabaseBackup">Backup(s) Details</a>'+
N'<ol>'+
N'<li><a href="#DatabaseBackup1">Full Database Backup </a></li>'+
N'<li><a href="#DatabaseBackup2">Access to Tlog</a></li>'+
N'<li><a href="#DatabaseBackup3">Transaction Log Backup(s) Size</a></li>'+
N'<li><a href="#DatabaseBackup4">Backup Software Check</a></li>'+
N'<li><a href="#DatabaseBackup5">Encrypted or Compressed TLog Backup</a></li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#DataTypeDetails">DataType Details</a>'+
N'<ol>'+
N'<li><a href="#DataTypeDetails1">LOB data types</a></li>'+
N'<li><a href="#DataTypeDetails2">Binary Data Types</a></li>'+
N'<li><a href="#DataTypeDetails3">Special Data Types</li>'+
N'<li><a href="#DataTypeDetails4">Spatial Data Types</li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#TableDetails">Table Details</a>'+
N'<ol>'+
N'<li><a href="#TableDetails1">Tables with Identity Columns </a></li>'+
N'<li><a href="#TableDetails2">Tables with Sparse Columns</a></li>'+
N'<li><a href="#TableDetails3">Temporal Tables</a></li>'+
N'<li><a href="#TableDetails4">Tables with Computed Columns</a></li>'+
N'<li><a href="#TableDetails5">Memory Optimized Tables</a></li>'+
N'<li><a href="#TableDetails6">Tables with Column Store Indexes</a></li>'+
N'<li><a href="#TableDetails7">Partitioned Tables</a></li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#PotentialIssues">Potential Issues</a>'+
N'<ol>'+
N'<li><a href="#PotentialIssues1">Finding tables with no PK index</a></li>'+
N'</ol>'+
N'</li>'+
N'<li><a href="#UsefulLinks">Useful Links</a>'+
N'</div>';

SET @header0=
N'<p id="Overview"><h1>Overview</h1></p>'+
N'<p id="Overview">This is the output from the DMS Support script for SQLServer Source.</p>'+
N'<p id="Overview">Please upload this to AWS Support via a Customer Support Case. </p>'

SET @header1=
N'<p id="DatabaseConfiguration"><h1>SQLServer Configuration</h1></p>'+
N'<p id="DatabaseConfiguration1"><h2>SQLServer Version :</h2></p>'+
N'<p id="DatabaseConfiguration1">AWS DMS supports, as a source, Microsoft SQL Server versions 2005, 2008, 2008R2, 2012, 2014, 2016, 2017, and 2019 on-premise databases and Amazon EC2 instance databases. </p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html">Please click this link for detailed information on supported versions.</a></p>'

-- Query The MS SQL Server instance to check product version.
SET @Table1='<table border="1">' +
N'<tr>' +
N'<th width="120">SQLServerVersion</th>' +
N'<th width="360">ProductVersion</th>' +
N'</tr>' + + CHAR(10);

SELECT @Result1 =
       CONVERT(nvarchar(max),
              (SELECT td = CASE cast(left(cast(serverproperty('productversion') as varchar), 4) as decimal(4, 2))
       WHEN 8.00 THEN 2000
       WHEN 9.00 THEN 2005
       WHEN 10.00 THEN 2008
       WHEN 10.50 THEN 2008
       WHEN 11.00 THEN 2012
       WHEN 12.00 THEN 2014
       WHEN 13.00 then 2016
       WHEN 14.00 then 2017
       WHEN 15.00 then 2019
       ELSE 0
   END,'', td = @@version FOR XML PATH, TYPE));


SET @html1 = @header + @header0+@header1+ @Table1 + CHAR(10) + @Result1 +
            N'</table>';

--Check for Empty Result Set
IF (@html1 is null)
--PRINT 'ITS NULL'
SET @html1 = @header+ @header0+@header1+ @Table1 + CHAR(10) +
              N'</table>';

-- Query The MS SQL Server instance to check, if it is set up for Replication.

SET @header2=
N'<p id="DatabaseConfiguration2"><h2>MS Replication Distributor:</h2></p>'+
N'<p id="DatabaseConfiguration2">AWS DMS supports, requires source SQL Server instance to be configured for distribution database for ongoing replication.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html">Please click this link for detailed information on requirements.</a></p>'

SET @Table2='<table border="1">' +
N'<tr>' +
N'<th width="250">Replication Distributor</th>' +
N'<th width="250">Product</th>' +
N'<th width="250">Provider</th>' +
N'<th width="250">Data Source</th>' +
N'</tr>'  + CHAR(10);

SELECT @Result2 =
       CONVERT(nvarchar(max), (SELECT
	   td=name,'',
	   td=product,'',
	   td=provider,'',
	   td=data_source FROM sys.servers WHERE name='repl_distributor' AND is_distributor=1 FOR XML PATH, TYPE));

SET @html2 = @header2+ @Table2 + CHAR(10) + @Result2 +
              N'</table>';

--Check for Empty Result Set
IF (@html2 is null)
--PRINT 'ITS NULL'
SET @html2 = @header2+ @Table2 + CHAR(10) +
              N'</table>';

--Query AlwaysOn Configuration Details

SET @header3=
N'<p id="DatabaseConfiguration3"><h2>AlwaysOn Configuration Details:</h2></p>'+
N'<p id="DatabaseConfiguration3"><h2>Members Details:</h2></p>'+
N'<p id="DatabaseConfiguration3">The SQL Server AlwaysOn Availability Groups feature is a high-availability and disaster-recovery solution that provides an enterprise-level alternative to database mirroring. To use AlwaysOn Availability Groups as a source in AWS DMS, you have to follow below steps.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.AlwaysOn">Use AlwaysOn Availability Groups as a source in AWS DMS</a></p>'

SET @Table3='<table border="1">' +
N'<tr>' +
N'<th width="120">Member Name</th>' +
N'<th width="120">Member Type</th>' +
N'<th width="120">Member State </th>' +
N'</tr>' ;

-- Skip Query for SQL Server 2008
IF (Substring (@Result1,10,4)='2008') GOTO SKIP_QUERY

SELECT @Result3 =
       CONVERT(nvarchar(max), (SELECT td=member_name,'',
 td=member_type_desc,'',
 td=member_state_desc, ''
 from sys.dm_hadr_cluster_members FOR XML PATH(N'tr'),TYPE));

SKIP_QUERY:

SET @html3 = @header3+ @Table3 + CHAR(10) + @Result3 +
              N'</table>';

--Check for Empty Result Set
IF (@html3 is null)
--PRINT 'ITS NULL'
SET @html3 = @header3+ @Table3 + CHAR(10) +
              N'</table>';


SET @header4=
N'<p id="DatabaseConfiguration4"><h2>Primary Replica Details:</h2></p>'

SET @Table4='<table border="1">' +
N'<tr>' +
N'<th width="120">Availability Group</th>' +
N'<th width="120">SQL cluster node name</th>' +
N'<th width="120">Replica Role </th>' +
N'<th width="120">Listener Name </th>' +
N'</tr>' ;

-- Skip Query for SQL Server 2008
IF (Substring (@Result1,10,4)='2008') GOTO SKIP_QUERY_1

SELECT @Result4 =
       CONVERT(nvarchar(max), (SELECT
  td= AGC.name,'',
  td=RCS.replica_server_name,'',
  td=ARS.role_desc,'',
  td=AGL.dns_name,''
FROM
 sys.availability_groups_cluster AS AGC
  INNER JOIN sys.dm_hadr_availability_replica_cluster_states AS RCS
   ON
    RCS.group_id = AGC.group_id
  INNER JOIN sys.dm_hadr_availability_replica_states AS ARS
   ON
    ARS.replica_id = RCS.replica_id
  INNER JOIN sys.availability_group_listeners AS AGL
   ON
    AGL.group_id = ARS.group_id
WHERE ARS.role_desc = 'PRIMARY' FOR XML PATH(N'tr'),TYPE));

SKIP_QUERY_1:

SET @html4 = @header4+ @Table4 + CHAR(10) + @Result4 +
              N'</table>';

--Check for Empty Result Set
IF (@html4 is null)
--PRINT 'ITS NULL'
SET @html4 = @header4+ @Table4 + CHAR(10) +
              N'</table>';

--Query SQLServer Database Size
SET @header5=
N'<p id="DatabaseDetails"><h1>Database Details</h1></p>'+
N'<p id="DatabaseDetails1"><h2>Database Size:<h2></p>'

SET @Table5='<table border="1">' +
N'<tr>' +
N'<th width="120">Database Name</th>' +
N'<th width="120">Size GB </th>' +
N'</tr>' ;
SELECT @Result5 =
       CONVERT(nvarchar(max), (SELECT
	   td=sys.databases.name,'',
       td= CONVERT(VARCHAR,SUM(size)*8/1024/1024),''
FROM        sys.databases
JOIN        sys.master_files
ON          sys.databases.database_id=sys.master_files.database_id
--where sys.databases.database_id=db_id()
WHERE sys.databases.database_id=db_id()
GROUP BY    sys.databases.name
ORDER BY    sys.databases.name  FOR XML PATH(N'tr'),TYPE));

SET @html5 = @header5+ @Table5 + CHAR(10) + @Result5 +
              N'</table>';

--Check for Empty Result Set
IF (@html5 is null)
SET @html5 = @header5+ @Table5 + CHAR(10) +
              N'</table>';

-- Query Database Recovery Model

SET @header6=
N'<p id="DatabaseDetails2"><h2>Database Recovery Model:</h2></p>'+
N'<p id="DatabaseDetails2">While using ongoing replication with a SQL Server database as a source for AWS DMS the recovery model must be set to Bulk logged or Full.
</p>'

SET @Table6='<table border="1">' +
N'<tr>' +
N'<th width="250">Database Name</th>' +
N'<th width="250">Recovery Model</th>' +
N'</tr>'  + CHAR(10);

SELECT @Result6 =
       CONVERT(nvarchar(max), (SELECT
	   td=name,'',
	   td = recovery_model_desc ,''
	   from master.sys.databases where database_id=db_id() FOR XML PATH(N'tr'), TYPE));

SET @html6 = @header6+ @Table6 + CHAR(10) + @Result6 +
              N'</table>';

--Check for Empty Result Set
IF (@html6 is null)
--PRINT 'ITS NULL'
SET @html6 = @header6+ @Table6 + CHAR(10) +
              N'</table>';

-- Query MS-Replication is properly set up on the database instance

SET @header7=
N'<p id="DatabaseDetails3"><h2>Replication Property:</h2></p>'+
N'<p> This information will help determine if MS-Replication is properly set up on the database instance.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.CDC">For more information using ongoing replication (CDC) from a SQL Server source </a></p>'


SET @Table7='<table border="1">' +
N'<tr>' +
N'<th width="250">Database Replication Setting</th>' +
N'</tr>' ;

SELECT @Result7 =
       CONVERT(nvarchar(max), (SELECT td = CASE count(*) WHEN 0 THEN 'Not Published for Transactional Replication' ELSE 'Published for Transactional Replication' END from master..sysdatabases d where d.dbid=db_id() and (category & 1)<>0 FOR XML PATH(N'tr'), TYPE));

SET @html7 = @header7+ @Table7 + CHAR(10) + @Result7 +
              N'</table>';

--Check for Empty Result Set
IF (@html7 is null)
--PRINT 'ITS NULL'
SET @html7 = @header7+ @Table7 + CHAR(10) +
              N'</table>';

--Query Associated code page value

SET @header8=
N'<p id="DatabaseDetails4"><h2>Associated Code Page:</h2></p>'+
N'<p>During AWS DMS ongoing replication, this information could help while troubleshooting data related issues.The code page determines the mapping between characters and the byte representation that is stored in the database table. </p>'

SET @Table8='<table border="1">' +
N'<tr>' +
N'<th width="250">Database Code Page</th>' +
N'</tr>' ;
SELECT @Result8 =
       CONVERT(nvarchar(max), (SELECT td=CAST( COLLATIONPROPERTY([Name], 'CodePage') AS INT) FROM ::fn_helpcollations() where [Name] =  DATABASEPROPERTYEX(DB_NAME(), 'Collation') FOR XML PATH(N'tr'),TYPE));

SET @html8 = @header8+ @Table8 + CHAR(10) + @Result8 +
              N'</table>';

--Check for Empty Result Set
IF (@html8 is null)
--PRINT 'ITS NULL'
SET @html8 = @header8+ @Table8 + CHAR(10) +
              N'</table>';

--Query to check if it's RDS Database

SET @header9=
N'<p id="DatabaseDetails5"><h2>Is RDS Database:</h2></p>'

SET @Table9='<table border="1">' +
N'<tr>' +
N'<th width="250">RDS Database</th>' +
N'</tr>' ;
SELECT @Result9 =
       CONVERT(nvarchar(max), ( SELECT td=CASE WHEN db_id('rdsadmin') IS NULL THEN 'No' ELSE 'Yes' END,'' FOR XML PATH(N'tr'),TYPE));

SET @html9 = @header9+ @Table9 + CHAR(10) + @Result9 +
              N'</table>';

--Check for Empty Result Set
IF (@html9 is null)
--PRINT 'ITS NULL'
SET @html9 = @header9+ @Table9 + CHAR(10) +
              N'</table>';

-- Query if SQL Server database is encrypted.

SET @header10=
N'<p id="DatabaseDetails6"><h2>Database Encryption:</h2></p>'+
N'<p>While using AWS DMS, Transparent Data Encryption (TDE) is not supported. Note that when accessing the backup transaction logs using SQL Server native functionality, TDE encryption is supported. Please note that column-level encryption is not supported.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.Limitations">For more information follow limitations on using SQL Server as a source for AWS DMS
</a></p>'


SET @Table10='<table border="1">' +
N'<tr>' +
N'<th width="125">Note:</th>' +
N'</tr>' ;

SELECT @Result10 =
       CONVERT(nvarchar(max), (SELECT td='As this is critical information, we are not collecting it.' FOR XML PATH(N'tr'),TYPE));

SET @html10 = @header10+ @Table10 + CHAR(10) + @Result10 +
              N'</table>';

--Check for Empty Result Set
IF (@html10 is null)
--PRINT 'ITS NULL'
SET @html10 = @header10+ @Table10 + CHAR(10) +
              N'</table>';

-- Query Login Permissions.

SET @header11=
N'<p id="Permissions"><h1>Permissions</h1></p>'+
N'<p id="ServerPermissions">You can set up ongoing replication for a SQL Server database source that does not require the user account to have sysadmin privileges.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.CDC">Using ongoing replication (CDC) from a SQL Server source
</a></p>'+
N'<p id="ServerPermissions"><h2>Server Level:</h2></p>'


SET @Table11='<table border="1">' +
N'<tr>' +
N'<th width="125">Entity</th>' +
N'<th width="100">Permission Name</th>' +
N'</tr>' ;

SELECT @Result11 =
       CONVERT(nvarchar(max), (SELECT td=entity_name,'',td=permission_name,''  FROM fn_my_permissions (NULL, 'SERVER')
         FOR XML PATH(N'tr'),TYPE))

SET @html11 = @header11+ @Table11 + CHAR(10) + @Result11 +
              N'</table>';

--Check for Empty Result Set
IF (@html11 is null)
--PRINT 'ITS NULL'
SET @html11 = @header11+ @Table11 + CHAR(10) +
              N'</table>';

SET @header12=
N'<p id="DatabasePermissions"><h2>Database Level:</h2></p>'


SET @Table12='<table border="1">' +
N'<tr>' +
N'<th width="125">Entity</th>' +
N'<th width="100">Permission Name</th>' +
N'</tr>' ;

SELECT @Result12 =
       CONVERT(nvarchar(max), (SELECT td=entity_name,'',td=permission_name,''  FROM fn_my_permissions (NULL, 'DATABASE')
         FOR XML PATH(N'tr'),TYPE))

SET @html12 = @header12+ @Table12 + CHAR(10) + @Result12 +
              N'</table>';

--Check for Empty Result Set
IF (@html12 is null)
--PRINT 'ITS NULL'
SET @html12 = @header12+ @Table12 + CHAR(10) +
              N'</table>';

SET @header13=
N'<p id="SysadminPermissions"><h2>Is SysAdmin?:</h2></p>'

SET @Table13='<table border="1">' +
N'<tr>' +
N'<th width="200">SysAdmin Permission:</th>' +
N'</tr>' ;

SELECT @Result13 =
       CONVERT(nvarchar(max), (SELECT td = 'Please check public doc for SysAdmin Permission requirements.','' FOR XML PATH(N'tr'),TYPE))

SET @html13 = @header13+ @Table13 + CHAR(10) + @Result13 +
              N'</table>';

--Check for Empty Result Set
IF (@html13 is null)
--PRINT 'ITS NULL'
SET @html13 = @header13+ @Table13 + CHAR(10) +
              N'</table>';

-- Query if No FULL database backup found (under the 'FULL' recovery model). To enable all changes to be captured with DMS, you must perform a full database backup.

SET @header14=
N'<p id="DatabaseBackup"><h1>Backup(s) Details</h1></p>'+
N'<p id="DatabaseBackup1"><h2>Full Database Backup:</h2></p>'+
N'<p> While using AWS DMS for ongoing replication, SQL Server must be configured for full backups, and you must perform a backup before beginning to replicate data.</p>'

SET @Table14='<table border="1">' +
N'<tr>' +
N'<th width="120">Full Backup Count</th>' +
N'</tr>' ;
SELECT @Result14 =
       CONVERT(nvarchar(max), (SELECT td=count(*)
 FROM msdb.dbo.backupset s
 INNER JOIN msdb.dbo.backupmediafamily m ON s.media_set_id = m.media_set_id
 WHERE s.database_name = DB_NAME() and s.[type]='D'
 and s.recovery_model in ('FULL','BULK-LOGGED') FOR XML PATH(N'tr'),TYPE));

SET @html14 = @header14+ @Table14 + CHAR(10) + @Result14 +
              N'</table>';

--Check for Empty Result Set
IF (@html14 is null)
--PRINT 'ITS NULL'
SET @html14 = @header14+ @Table14 + CHAR(10) +
              N'</table>';

-- Query if Access to TLOG is permitted

SET @header15=
N'<p id="DatabaseBackup2"><h2>Access to TLOG:</h2></p>'+
N'<p>During CDC, AWS DMS needs to look up SQL Server transaction log backups to read changes and this will ensure if DMS using is haing access to TLog.</p>'+
N'<p>We are skipping this check for RDS SQLServer.</p>'

SET @Table15='<table border="1">' +
N'<tr>' +
N'<th width="120">Current LSN</th>' +
N'</tr>' ;

-- SKIP Current LSN if its RDS SQL Server
IF (@html9 is not null) GOTO SKIPRDS

SELECT @Result15 =  CONVERT(nvarchar(max), (select top 1 td=[Current LSN] from fn_dblog(null,null) FOR XML PATH(N'tr'),TYPE));

SKIPRDS:

SET @html15 = @header15+ @Table15 + CHAR(10) + @Result15 +
              N'</table>';

--Check for Empty Result Set
IF (@html15 is null)
--PRINT 'ITS NULL'
SET @html15 = @header15+ @Table15 + CHAR(10) +
              N'</table>';

SET @header16=
N'<p id="DatabaseBackup3"><h2>Transaction Log Backup Size:</h2></p>'+
N'<p>During CDC, AWS DMS needs to look up SQL Server transaction log backups to read changes and this information will give idea to know transaction log backups information (mainly size) during last 7 days.</p>'

SET @Table16='<table border="1">' +
N'<tr>' +
N'<th width="120">Server Name</th>' +
N'<th width="120">Database Name</th>' +
N'<th width="120">Last Backup Date</th>' +
N'<th width="120">Backup Start Date</th>' +
N'<th width="120">BackupSize MB</th>' +
N'<th width="120">BackupSize GB</th>' +
N'<th width="120">Logical Device Name</th>' +
N'<th width="120">Physical Device Name</th>' +
N'</tr>' ;

SELECT  @Result16 =
CONVERT(nvarchar(max), (SELECT td= A.[Server],'',
   td=A.DATABASE_NAME,'',
   td=A.last_db_backup_date,'',
   td=B.backup_start_date,  '',
   td=CAST(CAST(b.backup_size / 1000000 AS INT) AS VARCHAR(14)),'',
   td=CAST(CAST(b.backup_size / 1000000000 AS INT) AS VARCHAR(14)),'',
   td=ISNULL(B.logical_device_name,'No Logial Name'),'',
   td=   (REVERSE(SUBSTRING(REVERSE(RIGHT(B.physical_device_name, ISNULL(NULLIF(CHARINDEX('\', REVERSE(B.physical_device_name))-1,-1),LEN(B.physical_device_name)))),
                       CHARINDEX('.', REVERSE(B.physical_device_name)) + 1, 999))),''
FROM
   (
   SELECT
       CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server,
       msdb.dbo.backupset.database_name,
       msdb.dbo.backupset.backup_finish_date AS last_db_backup_date
   FROM    msdb.dbo.backupmediafamily
       INNER JOIN msdb.dbo.backupset
       ON msdb.dbo.backupmediafamily.media_set_id = msdb.dbo.backupset.media_set_id
   WHERE   msdb..backupset.type = 'l'  and msdb.dbo.backupset.database_name=DB_NAME()
   ) AS A
   LEFT JOIN
   (
   SELECT
   CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server,
   msdb.dbo.backupset.database_name,
   msdb.dbo.backupset.backup_start_date,
   msdb.dbo.backupset.backup_finish_date,
   msdb.dbo.backupset.expiration_date,
   msdb.dbo.backupset.backup_size,
   msdb.dbo.backupmediafamily.logical_device_name,
   msdb.dbo.backupmediafamily.physical_device_name,
   msdb.dbo.backupset.name AS backupset_name,
   msdb.dbo.backupset.description
FROM   msdb.dbo.backupmediafamily
   INNER JOIN msdb.dbo.backupset ON msdb.dbo.backupmediafamily.media_set_id = msdb.dbo.backupset.media_set_id
WHERE  msdb..backupset.type = 'l'
   ) AS B
   ON A.[server] = B.[server] AND A.[database_name] = B.[database_name] AND A.[last_db_backup_date] = B.[backup_finish_date]
WHERE backup_start_date BETWEEN DATEADD(dd, -7, GETDATE()) AND GETDATE()
ORDER BY
   A.database_name FOR XML PATH(N'tr'), TYPE));


SET @html16 = @header16+ @Table16 + CHAR(10) + @Result16+
              N'</table>';

IF (@html16 is null)
--PRINT 'ITS NULL'
SET @html16 = @header16+ @Table16 + CHAR(10) +
              N'</table>';

-- Query for Third-Party Backup Software

SET @header17=
N'<p id="DatabaseBackup4"><h2>Backup Software:</h2></p>'+
N'<p>During CDC, AWS DMS needs to look up SQL Server transaction log backups to read changes. AWS DMS does not support using SQL Server transaction log backups that were created using third-party backup software.</p>'

SET @Table17='<table border="1">' +
N'<tr>' +
N'<th width="150">Software Name</th>' +
N'<th width="100">Third Party?</th>' +
N'</tr>' ;

SELECT @Result17 =
       CONVERT(nvarchar(max), (SELECT top 1 td=software_name,'',
	   td=CASE software_name WHEN 'Microsoft SQL Server' THEN 'NO' ELSE 'YES' END,''
	   FROM msdb.dbo.backupmediaset
 FOR XML PATH(N'tr'),TYPE));

SET @html17 = @header17+ @Table17 + CHAR(10) + @Result17 +
              N'</table>';

--Check for Empty Result Set
IF (@html17 is null)
--PRINT 'ITS NULL'
SET @html17 = @header17+ @Table17 + CHAR(10) +
              N'</table>';

--Query for Encrypted or Compressed TLog Backup

SET @header18=
N'<p id="DatabaseBackup5"><h2>Encrypted or Compressed TLog Backup:</h2></p>'+
N'<p>During CDC, AWS DMS needs to look up SQL Server transaction log backups to read changes. AWS DMS does not support Encrypted  and Compressed backup transaction logs.</p>'


SET @Table18='<table border="1">' +
N'<tr>' +
N'<th width="750">As this is critical information, we are not collecting this. Please check AWS DMS public documentation</th>' +
N'</tr>';

SET @html18 = @header18+ @Table18 + CHAR(10) + @Result18 +
              N'</table>';

IF (@html18 is null)
--PRINT 'ITS NULL'
SET @html18 = @header18+ @Table18 + CHAR(10) +
              N'</table>';

--Query lists of tables that cointain columns with LOB data types.
--Large objects in SQL Server are columns with following data types: varchar(max), nvarchar(max), text, ntext, image, varbinary(max), and xml.

SET @header19=
N'<p id="DataTypeDetails"><h1>DataType Details</h1></p>'+
N'<p id="DataTypeDetails1"><h2>Tables with LOB data types:</h2></p>'+
N'<p>AWS DMS provides full support for using large object data types (BLOBs, CLOBs, and NCLOBs) for SQL Server source.During CDC, AWS DMS supports CLOB data types only in tables that include a primary key.
</p>'+
N'<p> Follow below best practices while migrating LOBs.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html#CHAP_BestPractices.LOBS">Migrating large binary objects (LOBs)
</a></p>'


SET @Table19='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'<th width="100">No of Objects</th>' +
N'</tr>' ;

SELECT @Result19 =
       CONVERT(nvarchar(max), (SELECT td= t.table_schema,'',
       td=t.table_name,'',
       td=count(*),''
from information_schema.columns c
    inner join INFORMATION_SCHEMA.tables t
        on c.TABLE_SCHEMA = t.TABLE_SCHEMA
        and c.TABLE_NAME = t.TABLE_NAME
where t.TABLE_TYPE = 'BASE TABLE' and c.TABLE_SCHEMA<>'cdc'
and ((c.data_type in ('VARCHAR', 'NVARCHAR') and c.character_maximum_length = -1)
or data_type in ('TEXT', 'NTEXT', 'IMAGE', 'VARBINARY', 'XML', 'FILESTREAM'))
group by t.table_schema,
    t.table_name
order by t.table_schema,
    t.table_name  FOR XML PATH(N'tr'),TYPE));

SET @html19 = @header19+ @Table19 + CHAR(10) + @Result19 +
              N'</table>';

--Check for Empty Result Set
IF (@html19 is null)
--PRINT 'ITS NULL'
SET @html19 = @header19+ @Table19 + CHAR(10) +
              N'</table>';

-- Query to check Binary Data Types

SET @header20=
N'<p id="DataTypeDetails2"><h2>Binary Data Types:</h2></p>'+
N'<p>Some additional information about Binary Data Types at source data base.</p>'


SET @Table20='<table border="1">' +
N'<tr>' +
N'<th width="120">Schema Name</th>' +
N'<th width="120">Table NameN</th>' +
N'<th width="120">Column Name</th>' +
N'<th width="120">DataType</th>' +
N'</tr>' ;

SELECT @Result20 =
       CONVERT(nvarchar(max), (SELECT td=S.name,'',
	   td=T.name,'',
       td=C.name,'',
	   td=ty.name
FROM sys.columns C
  JOIN sys.types ty
    ON C.system_type_id = ty.system_type_id
  JOIN sys.tables T
    ON C.object_id = T.object_id
  JOIN sys.schemas S
    ON T.schema_id = S.schema_id
WHERE ty.name IN ('binary', 'varbinary', 'image')
ORDER BY S.name, T.name, C.name, ty.name FOR XML PATH(N'tr'),TYPE));

SET @html20 = @header20+ @Table20 + CHAR(10) + @Result20 +
              N'</table>';


--Check for Empty Result Set
IF (@html20 is null)
--PRINT 'ITS NULL'
SET @html20 = @header20+ @Table20 + CHAR(10) +
              N'</table>';

-- Query Tables that include fields with the following data types:
--CURSOR
--SQL_VARIANT
--TABLE

SET @header21=
N'<p id="DataTypeDetails3"><h2>Special Data Types:</h2></p>'+
N'<p id="DataTypeDetails3">AWS DMS does not support tables that include fields with the following data types. i.e CURSOR,SQL_VARIANT,TABLE.</p>'+
N'<p id="DataTypeDetails3">Please follow documentation link to check all supporeted data types. https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html </p>'

SET @Table21='<table border="1">' +
N'<tr>' +
N'<th width="150">Table Name</th>' +
N'<th width="150">Column Name</th>' +
N'<th width="150">Variable Name</th>' +
N'</tr>';

SELECT @Result21 =
       CONVERT(nvarchar(max), ( SELECT
	   td=OBJECT_NAME(c.object_id),'',
	   td=c.name,'',
	   td=t.name,''
FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE t.name IN ('CURSOR','TABLE','SQL_VARIANT') and OBJECT_NAME(c.object_id) not like 'sys%'
ORDER BY 1, 2 FOR XML PATH(N'tr'),TYPE));

SET @html21= @header21+ @Table21 + CHAR(10) + @Result21 +
              N'</table>';

--Check for Empty Result Set
IF (@html21 is null)
--PRINT 'ITS NULL'
SET @html21 = @header21+ @Table21 + CHAR(10) +
              N'</table>';

--The query below lists all columns with spatial data types.

SET @header22=+
N'<p id="DataTypeDetails4"><h2>Spatial Data Types</h2></p>'+
N'<p id="DataTypeDetails4">When inserting a value into SQL Server spatial data types (GEOGRAPHY and GEOMETRY), you can either ignore the SRID (Spatial Reference System Identifier) property or specify a different number. When replicating tables with spatial data types, AWS DMS replaces the SRID with the default SRID (0 for GEOMETRY and 4326 for GEOGRAPHY).</p>'


SET @Table22='<table border="1">' +
N'<tr>' +
N'<th width="150">Table Name</th>' +
N'</tr>'+ CHAR(10);

SELECT @Result22 =
       CONVERT(nvarchar(max), ( select
	   td=c.name,''
from sys.columns c
join sys.tables t
     on t.object_id = c.object_id
where type_name(user_type_id) in ('geometry', 'geography') FOR XML PATH(N'tr'),TYPE));

SET @html22= @header22+ @Table22 + CHAR(10) + @Result22 +
              N'</table>';

IF (@html22 is null)
SET @html22 = @header22+ @Table22 + CHAR(10) +
              N'</table>';

-- Query SQLServer Tables with Identity Columns

SET @header23=
N'<p id="TableDetails"><h1>Tables Details </h1></p>'+
N'<p id="TableDetails1"><h2>Tables with Identity Columns: </h2></p>'+
N'<p> During AWS DMS ongoing replication the identity property for a column is not migrated to a target database column. It should be taken care manually on target. </p>'

SET @Table23='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'</tr>' ;

SELECT @Result23 =
       CONVERT(nvarchar(max), (SELECT
 td= s.name,'',
 td= t.name,''
FROM sys.schemas AS s
INNER JOIN sys.tables AS t
  ON s.[schema_id] = t.[schema_id]
WHERE EXISTS
(
  SELECT 1 FROM sys.identity_columns
    WHERE [object_id] = t.[object_id]
) FOR XML PATH(N'tr'),TYPE));

SET @html23 = @header23+ @Table23 + CHAR(10) + @Result23 +
              N'</table>';

--Check for Empty Result Set
IF (@html23 is null)
--PRINT 'ITS NULL'
SET @html23 = @header23+ @Table23 + CHAR(10) +
              N'</table>';


--Query SQLServer Tables for Sparse Columns
--A list of all columns that use the SPARSE property can be obtained via the is_sparse field in sys.columns:

SET @header24=
N'<p id="TableDetails2"><h2>Tables with Sparse Columns:</h2></p>'+
N'<p>The SQL Server endpoint does not support the use of tables having sparse columns.</p>'

SET @Table24='<table border="1">' +
N'<tr>' +
N'<th width="150">Table Name</th>' +
N'<th width="100">Column Name</th>' +
N'</tr>' ;

SELECT @Result24 =
       CONVERT(nvarchar(max), (SELECT
	   td= so.name,'',
	   td= sc.name,''
FROM sys.columns sc
JOIN sys.objects so
ON so.OBJECT_ID = sc.OBJECT_ID
WHERE is_sparse = 1 FOR XML PATH(N'tr'),TYPE));

SET @html24 = @header24+ @Table24 + CHAR(10) + @Result24 +
              N'</table>';

--Check for Empty Result Set
IF (@html24 is null)
--PRINT 'ITS NULL'
SET @html24 = @header24+ @Table24 + CHAR(10) +
              N'</table>';


--Query SQLServer Database for Temporal Tables

SET @header25=
N'<p id="TableDetails3"><h2>Temporal Tables:</h2></p>'+
N'<p>The SQL Server endpoint does not support the use of Temporal Tables.</p>'

SET @Table25='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'</tr>' ;

-- Skip Query for SQL Server 2008
IF (Substring (@Result1,10,4)='2008') GOTO SKIP_QUERY_3

/*SELECT @Result25 =
       CONVERT(nvarchar(max), (SELECT td=schema_name(t.schema_id),'',
    td=t.name,''
from sys.tables t
    left outer join sys.tables h
        on t.history_table_id = h.object_id
where t.temporal_type = 2
 FOR XML PATH(N'tr'),TYPE)); */

SKIP_QUERY_3:

SET @html25 = @header25+ @Table25 + CHAR(10) + @Result25 +
              N'</table>';

--Check for Empty Result Set
IF (@html25 is null)
--PRINT 'ITS NULL'
SET @html25 = @header25+ @Table25 + CHAR(10) +
              N'</table>';

--Query SQLServer Tables for Computed Columns

SET @header26=
N'<p id="TableDetails4"><h2>Tables with Computed Columns:</h2></p>'+
N'<p>The SQL Server endpoint does not support the use of Computed Columns.</p>'

SET @Table26='<table border="1">' +
N'<tr>' +
N'<th width="150">Table Name</th>' +
N'<th width="100">Column Name</th>' +
N'</tr>' ;

SELECT @Result26 =
       CONVERT(nvarchar(max), (SELECT td= object_name(object_id),'',
	   td=name,''
FROM sys.columns
WHERE is_computed = 1
 FOR XML PATH(N'tr'),TYPE));

SET @html26 = @header26+ @Table26 + CHAR(10) + @Result26 +
              N'</table>';

--Check for Empty Result Set
IF (@html26 is null)
--PRINT 'ITS NULL'
SET @html26 = @header26+ @Table26 + CHAR(10) +
              N'</table>';

-- Query SQLServer Database for Memory Optimized Tables

SET @header27=
N'<p id="TableDetails5"><h2>Memory Optimized Tables:</h2></p>'+
N'<p>CDC operations are not supported on memory-optimized tables. This limitation applies to SQL Server 2014 (when the feature was first introduced) and later.</p>'

SET @Table27='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'<th width="100">Memory Optimized</th>' +
N'</tr>' ;

IF (Substring (@Result1,10,4)='2008') GOTO SKIP_QUERY_4

SELECT @Result27 =
       CONVERT(nvarchar(max), (SELECT td=SCHEMA_NAME(Schema_id),'',
td=name,'',
td=is_memory_optimized,''
FROM sys.tables where is_memory_optimized=1 FOR XML PATH(N'tr'),TYPE));

SKIP_QUERY_4:
SET @html27 = @header27+ @Table27 + CHAR(10) + @Result27 +
              N'</table>';

--Check for Empty Result Set
IF (@html27 is null)
--PRINT 'ITS NULL'
SET @html27 = @header27+ @Table27 + CHAR(10) +
              N'</table>';

--Query SQLServer Database for ColumnStore Indexes

SET @header28=
N'<p id="TableDetails6"><h2>Tables with ColumnStore Indexes:</h2></p>'+
N'<p>The SQL Server endpoint does not support the tables with ColumnStore Indexes</p>'

SET @Table28='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="150">Table Name</th>' +
N'<th width="150">Index Name</th>' +
N'<th width="150">Index Type</th>' +
N'</tr>';

SELECT @Result28 =
       CONVERT(nvarchar(max), ( SELECT
 td=OBJECT_SCHEMA_NAME(OBJECT_ID),'',
 td=OBJECT_NAME(OBJECT_ID),'',
 td=i.name,'',
 td=i.type_desc,''
FROM sys.indexes AS i
WHERE is_hypothetical = 0 AND i.index_id <> 0
 AND i.type_desc IN ('CLUSTERED COLUMNSTORE','NONCLUSTERED COLUMNSTORE') FOR XML PATH(N'tr'),TYPE));

SET @html28 = @header28+ @Table28 + CHAR(10) + @Result28 +
              N'</table>';

IF (@html28 is null)
--PRINT 'ITS NULL'
SET @html28 = @header28+ @Table28 + CHAR(10) +
              N'</table>';

-- Query SQLServer database for Partitioned tables.

SET @header29=
N'<p id="TableDetails7"><h2>Partitioned Tables:</h2></p>'+
N'<p>During AWD DMS Full Load, You can use partition & sub partition auto feature to load all partitions of the table in parallel.Please note that the SQL Server endpoint does not support the SQL Server partition switching operation during ongoing replication.</p>'+
N'<p>Follow below link for more information.</p>'+
N'<p><a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TableMapping.html">Using table mapping to specify task settings</a></p>'


SET @Table29='<table border="1">' +
N'<tr>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'</tr>' ;

SELECT @Result29 =
       CONVERT(nvarchar(max), (Select
	   td=s.name ,'',
	   td=t.name,''
From sys.tables t
Inner Join sys.schemas s On t.schema_id = s.schema_id
Inner Join sys.partitions p on p.object_id = t.object_id
Where p.index_id In (0, 1)
Group By s.name, t.name
Having Count(*) > 1
Order By s.name, t.name FOR XML PATH(N'tr'),TYPE));

SET @html29 = @header29+ @Table29 + CHAR(10) + @Result29 +
              N'</table>';

--Check for Empty Result Set
IF (@html29 is null)
--PRINT 'ITS NULL'
SET @html29 = @header29+ @Table29 + CHAR(10) +
              N'</table>';

--Query to check Potential Issues
SET @header30=
N'<p id="PotentialIssues"><h1>Potential Issues</h1></p>'+
N'<p id="PotentialIssues1"><h2>Finding tables with no PK index:<h2></p>'

SET @Table30='<table border="1">' +
N'<tr>' +
N'<th width="150">Database Name</th>' +
N'<th width="150">Schema Name</th>' +
N'<th width="100">Table Name</th>' +
N'<th width="200">Is Tracked by MS-CDC ?</th>' +
N'</tr>' ;

SELECT @Result30 =
       CONVERT(nvarchar(max), (SELECT
	   td=DB_NAME(),'',
	   td=sc.name, '',
	   td=t.name,'',
	   td= CASE t.is_tracked_by_cdc WHEN 0 THEN 'No' ELSE 'YES' END
FROM sys.tables t
INNER JOIN sys.schemas sc ON t.schema_id = sc.schema_id
WHERE OBJECTPROPERTY(t.object_id,'TableHasPrimaryKey') = 0
AND t.type = 'U' AND t.name not like 'sys%' AND t.name not like 'MS%' and sc.name not like 'sys%'
ORDER BY t.name FOR XML PATH(N'tr'),TYPE));

SET @html30 = @header30+ @Table30 + CHAR(10) + @Result30 +
              N'</table>';

--Check for Empty Result Set
IF (@html30 is null)
--PRINT 'ITS NULL'
SET @html30 = @header30+ @Table30 + CHAR(10) +
              N'</table>';

--Useful links
SET @header31=
N'<p id="UsefulLinks"><h1>Useful Links</h1></p>'+
N'<p>1.<a href="https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html">Using a Microsoft SQL Server database as a source for AWS DMS</a></p>'+
N'<p>2.<a href="https://aws.amazon.com/dms/resources/">Migration playbooks and step-by-step guides</a></p>'+
N'<p>3.<a href="https://docs.aws.amazon.com/dms/latest/sbs/CHAP_SQLServer2Aurora.Steps.html">Migrating a SQL Server Database to Amazon Aurora MySQL</a></p>'

SET @html31 = @header31+ CHAR(10) +
              N'</table>';

-- Generate Final Results

SET @html = @html1+@html2+@html3+@html4+@html5+@html6+@html7+@html8+@html9+@html10+@html11+@html12+@html13+@html14+@html15+@html16+@html17+@html18+@html19+@html20+@html21+@html22+@html23+@html24+@html25+@html26+@html27+@html28+@html29+@html30+@html31+
            N'</body></html>';

-- Print Final selection to return result.
SELECT @html;