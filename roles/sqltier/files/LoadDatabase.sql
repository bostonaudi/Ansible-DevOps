
--DROP DATABASE
	SET NOCOUNT ON;

	-- Enable xp_cmdshell. We should be admins.
	EXEC sp_configure'xp_cmdshell', 1;
	GO
	RECONFIGURE;
	GO

	Declare @databaseName as varchar(255)
	Declare @bakLocation as varchar(4000)
	Declare @computerName as varchar(50)

	Set @databaseName = '$(databaseName)'
	Set @bakLocation = '$(bakLocation)'
	Set @computerName = '$(computerName)'

	DECLARE @sql varchar(4000)
	DECLARE @snapshotName varchar(255)
	DECLARE @dropSQL varchar(4000)
	DECLARE @BaseRestore as varchar(4000)
	
	-- Drop the database if it already exists --		
	IF EXISTS (SELECT base.name from sys.databases base inner join sys.databases snap on snap.source_database_id = base.database_id where base.name = @databaseName)
	BEGIN
		SET @snapshotName = (SELECT top 1 snap.name from sys.databases base inner join sys.databases snap on snap.source_database_id = base.database_id where base.name = @databaseName)
		SELECT @SQL=COALESCE(@SQL,'')+'Kill '+CAST(spid AS VARCHAR(10))+ '; ' 
		FROM sys.sysprocesses 
		WHERE DBID=DB_ID(@snapshotName)
		 and cmd <> 'CHECKPOINT'
		 and cmd <> 'LAZY WRITER'
		 --and cmd <> 'AWAITING COMMAND'  --IIS keeps connection
		 and cmd <> 'LOCK MONITOR'
		 and cmd <> 'SIGNAL HANDLER'

		EXEC(@sql)
		
		SET @sql = 'DROP DATABASE [' + @snapshotName + ']'		
		EXEC(@sql)
	END

	IF  EXISTS (SELECT name FROM sys.databases WHERE name = @databaseName)
	BEGIN
		SELECT @SQL=COALESCE(@SQL,'')+'Kill '+CAST(spid AS VARCHAR(10))+ '; ' 
		FROM sys.sysprocesses 
		WHERE DBID=DB_ID(@databaseName)
		 and cmd <> 'CHECKPOINT'
		 and cmd <> 'LAZY WRITER'
		 --and cmd <> 'AWAITING COMMAND'  --IIS keeps connection
		 and cmd <> 'LOCK MONITOR'
		 and cmd <> 'SIGNAL HANDLER'

		EXEC(@sql)

		SELECT @sql=COALESCE(@sql, '') + 'DROP DATABASE [' + name + ']; '
		FROM sys.databases WHERE name = @databaseName
		
		EXEC(@sql)
	END 	

	--Get default data folder from registry - make sure instance name is correct!
	exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'DefaultData',@BaseRestore OUTPUT
   
	-- get default log folder
	declare @DefaultLogPath nvarchar(512)
	exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'DefaultLog',@DefaultLogPath OUTPUT
	      
	DECLARE @directoryExists int;
	DECLARE @fileResults as TABLE 
	(
		fileExists int,
		directoryExists int,
		parentExist int
	);

	-- Create a directory to store the DB instance for this computer -- 
	DECLARE @directory varchar(4000);
	DECLARE @logDirectory varchar(4000);
	DECLARE @CMD varchar(250);

	Set @directory = @BaseRestore + '\'+ @computerName + '\' + @databaseName;
	insert into @fileResults (fileExists, directoryExists, parentExist)
	EXECUTE xp_fileexist @directory; 
	select top 1 @directoryExists=directoryExists from @fileResults;

	IF (@directoryExists = 1) 
	BEGIN
			SELECT @CMD = 'rmdir /S /Q ' + char(34) + @directory + char(34) + ''
			EXECUTE xp_cmdshell @CMD , NO_OUTPUT
	END
	
	EXECUTE	xp_create_subdir @directory

	-- Create a directory to store the log files for the DB instance for this computer
	Set @logDirectory = @DefaultLogPath + '\'+ @computerName + '\' + @databaseName	
	insert into @fileResults (fileExists, directoryExists, parentExist)
	EXECUTE xp_fileexist @directory; 
	select top 1 @directoryExists=directoryExists from @fileResults;

	IF (@directoryExists = 1) 
	BEGIN
			SELECT @CMD = 'rmdir /S /Q ' + char(34) + @directory + char(34) + ''
			EXECUTE xp_cmdshell @CMD , NO_OUTPUT
	END
	
	EXECUTE	xp_create_subdir @logDirectory

	--split multiple bak's up
	--Declare @BAKLocations as varchar(max)
	--Select @BAKLocations=  Coalesce(@BAKLOCATIONS + ',','') + 'DISK = N''' + Value +'''' FROM UFN_STRINGSPLITTER(@bAKLocation,',')
	
	DECLARE @cmdForFileLIst varchar(250)
	SET @cmdForFileLIst = 'RESTORE FILELISTONLY FROM DISK = N''' + @BAKLocation + ''''
	
	DECLARE @filelist TABLE 
				(	
				lname varchar(128), 
				pname varchar(4000), 
				type varchar(10), 
				fgroup varchar(128), 
				size varchar(50), 
				maxsize varchar(50),
				lfield varchar(50),
				createlsn nvarchar(25),
				droplsn varchar(50),
				uniqueid varchar(50),
				readonlylsn varchar(50),
				readwritelsn varchar(50),
				backupsizeinbytes bigint,
				sourceblocksize varchar(50),
				lfilegroupid varchar(50),
				loggroupguid varchar(50),
				differbaselsn varchar(50),
				differbase varchar(50),
				isreadonly varchar(50),
				ispresent varchar(50),
				tdeprint varchar(50)
				)
	INSERT @filelist
	EXEC (@cmdForFileLIst)
	
	DECLARE @restoreSQL varchar(8000)

	SET @restoreSQL = ' RESTORE DATABASE [' + @databaseName  + '] FROM DISK = N''' + @BAKLocation + ''' WITH FILE = 1'	

	SELECT @restoreSQL = coalesce(@restoreSQL + ',', '') +
						 'MOVE N''' + f.lname + ''' TO N''' +
						 @directory + '\' +
						 substring(pname, len(pname) - CHARINDEX('\', REVERSE(pname)) + 2, 100) + ''''
	FROM @filelist f Where f.fgroup is not null

	SELECT @restoreSQL = coalesce(@restoreSQL + ',', '') +
						 'MOVE N''' + f.lname + ''' TO N''' +
						 @logDirectory + '\' +
						 substring(pname, len(pname) - CHARINDEX('\', REVERSE(pname)) + 2, 100) + ''''
	FROM @filelist f Where f.fgroup is null


	SET @restoreSQL = @restoreSQL + ', NOUNLOAD,  REPLACE,  STATS = 10'							 
	Select @restoreSQL
							  
	EXEC(@restoreSQL)
	
	--IF @Product = 'Infinity'
	--BEGIN
		-- Add Permissions
	DECLARE @permissionSQL varchar(8000)

	SET @permissionSQL = 'USE [' + @databaseName + '];' +
					 'IF  EXISTS (SELECT * FROM sys.database_principals WHERE name = N''PDNT\domain computers'')' +
					 'DROP USER [PDNT\domain computers];' +
					 'CREATE USER [PDNT\domain computers] FOR LOGIN [PDNT\domain computers];' +						 
					 'EXEC sp_addrolemember N''BBAPPFXSERVICEROLE'', N''PDNT\domain computers'';'
	BEGIN TRY
		EXEC(@permissionSQL)
	END TRY
	BEGIN CATCH
		
	END CATCH
	
	DECLARE @RegenEncrypt varchar(8000)
	
	SET @RegenEncrypt = 'USE [' + @databaseName + '];' +
						'open master key decryption by password = ''Bl@ckb@udEnterpr1s3R0x!!'';' +
						'alter master key regenerate with encryption by password = ''Bl@ckb@udEnterpr1s3R0x!!''; ' +
						'close master key;'
	BEGIN TRY
		EXEC(@RegenEncrypt)
	END TRY
	BEGIN CATCH
		
	END CATCH
	--END