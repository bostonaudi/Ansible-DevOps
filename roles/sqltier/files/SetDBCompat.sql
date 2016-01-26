SET NOCOUNT ON;

Declare @databasename as varchar(255);
Declare @compatLevel as varchar(100);

Set @databasename = '$(databasename)'
Set @compatLevel = '$(compatLevel)'

DECLARE @sql varchar(4000)

set @sql=
'USE [master]
ALTER DATABASE [' + @databasename + '] SET COMPATIBILITY_LEVEL = ' + @compatLevel;
exec (@sql);