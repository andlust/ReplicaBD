#Para Chamar o script = powerShell.exe -command "&'T:\Online\André\Totvs\Scripts_PowerShell\Clone_DB.ps1'"
#Verificar os arquivos dentro do backup
#$NomeArq     = invoke-sqlcmd -serverinstance $InstSrvOrig -Query "restore filelistonly from disk='$NomeArq'"
# Pegar o caminho das bases de dados
#$FileName     = $nomeFisico.Substring($nomeFisico.LastIndexOf('\') + 1 )
#$Path         = $nomeFisico.Substring(0,$nomeFisico.LastIndexOf('\') + 1 )
#$cmd = "SET LOCK_TIMEOUT -1 RESTORE DATABASE $BdDest FROM DISK ='$NomeArqOrig' WITH FILE = 1, RECOVERY, REPLACE $cmd "

Clear-Host
$DataAtual      =  Get-Date
$BkpToRest      =  Read-Host "[1] Clonar Banco de Dados [2] Restaurar a partir de um arquivo [3] Criar Banco de Dados novo"   

## Informações quando selecionado a criação de um banco novo
If ($BkpToRest -eq "3")
    {
        $CloneOrigem   =  Write-Host "[1] Criar Banco de dados a partir de clone do banco de origem [2] Criar Banco de dados a partir de arquivo" 
        $Banco         =  Write-Host "Nome do banco de dados "
        $DataFilePath  =  Write-Host "Infome o path dos arquivos de dados " 
        $respUser      =  Write-Host "Usuário " 
        $respLog       =  Write-Host "Login "

        If ($CloneOrigem -eq "1") 
            {
               $BkpToRest = "1" 
            }
        Else 
            {
               $BkpToRest = "2" 
            }
    }


#Preenchimento da instância de origem e banco de origem - Usado quando é clone de banco de dados
If ($BkpToRest -eq "1") 
    {
        $InstSrvOrig =  Read-Host  "Informe a Instância de Origem:  "
        $BdOrig      =  Read-Host  "Informe o Banco de Origem:  "
    } 

#Preenchimento quando a opção de restore for a partir de um arquivo de backup
If ($BkpToRest -eq "2") 
    {
        $BkpToRestPath  =  Read-Host "Informe o path incluindo o nome do arquivo: "  
        $StatusPath = Test-Path -path $BkpToRestPath 
        
        If (-Not $StatusPath) 
            {
                Write-Host "Arquivo de Backup não encontrado no path $BkpToRestPath"  
                Break
            } 
    }

$InstSrvDes     =  Read-Host "Informe a Instância de Destino: "
$BdDest         =  Read-Host "Informe o Banco de Destino: "

If ($BkpToRest -ne "3") {$PathBkp =  Read-Host "Informe local dos backups de segurança: " }

$cmd            =  ""
$VarAux         =  ""
$VarAuxU        =  ""
$PermissionUser =  ""
$DropUser       =  ""


#Processamento
Write-Host "Inicio do processamento: $DataAtual"
Import-Module -Name SQLPS -DisableNameChecking

##Pega as informações da base de destino / Pega as permissões do usuário
Try {
 
    If ($BkpToRest -eq "3") 
        {
          Write-Host "Opção 3"        
       
          $PermissionUser = "USE [$Banco] CREATE USER [$Usuario] FOR LOGIN [$Login] ALTER ROLE [$Permission] ADD MEMBER [$Usuario]  " + $PermissionUser   
       
       
        }         
    Else
        {
            #Obtém os datafiles para usá-los no restore da base de dados
            Write-Host "Obtendo o caminho dos DataFiles..."
            Set-Location SQLSERVER:\SQL\$InstSrvDes\Databases\$BdDest -ErrorAction Stop 
            $MontaQueryRestore = Invoke-SqlCmd -ServerInstance $InstSrvDes -Query "select * from sys.database_files" 
            Write-Host "Obtendo o caminho dos DataFiles... -----> OK "

            #Obtém as permissões de usuários 
            Write-Host "Obtendo permissoes do usuário..."
            Set-Location SQLSERVER:\SQL\$InstSrvDes\Databases\$BdDest -ErrorAction Stop 
            $QryGetPermission = "Use [$BdDest] Select sl.loginname As Login, sl.name As Usuario, sl.dbname As Banco, (SELECT name FROM sys.sysusers WHERE uid = sm.groupuid) AS Permissao "
            $QryGetPermission = $QryGetPermission + " from syslogins sl INNER JOIN sysusers su ON (sl.sid = su.sid) INNER JOIN sysmembers sm ON (su.uid = sm.memberuid) Where sl.dbname in ('$BdDest','master') "
            $MontaQueryPermission = Invoke-SqlCmd -ServerInstance $InstSrvDes -Query $QryGetPermission 
            Write-Host "Obtendo permissoes do usuário... -----> OK "

            Write-Host "Exibindo as informações dos usuários (Usuário/Permissão) "
            #Monta as queries para dropar e criar os usuários
            $MontaQueryPermission | ForEach-Object{
            $Login       = $_.Login
            $Usuario     = $_.Usuario
            $Banco       = $BdDest  #  $_.Banco
            $Permission  = $_.Permissao
        
            Write-Host $Usuario"/"$Permission        


            If  ($Usuario -ne $VarAux)  
                {
                     $PermissionUser = "USE [$Banco] CREATE USER [$Usuario] FOR LOGIN [$Login] ALTER ROLE [$Permission] ADD MEMBER [$Usuario]  " + $PermissionUser 
                }
           Else          
               {   
                      $PermissionUser = $PermissionUser + "USE [$Banco] ALTER ROLE [$Permission] ADD MEMBER [$Usuario] " 
               }      
        
           $VarAux = $Usuario
  
  
           If ( $Usuario -ne $VarAuxU) 
        
                {
                     $DropUser = $DropUser + " DROP USER IF EXISTS [$Usuario] " 
                }

               $VarAuxU = $Usuario }
        
            $DropUser = "USE [$Banco]" + $DropUser        
 

        }


    }
Catch
    {
        Write-Host "Falha ao acessar a instância/Banco de destino/usuário(s)" 
        Break 
    }    

        

##Bloco para fazer os backups das bases de dados
#Faz o backup da base de origem
#Só acessa o bloco abaixo caso consiga obter os datafiles do banco de destino
   
   ## Caso seja restaurado a partir de uma arquivo a rotina não faz backup da origem
   
             Try   
                 {
                    If ($BkpToRest -ne "2")
                        {    
                            Write-Host "Realizando Backup do Banco de origem..."
                            $NomeArqOrig    =  $PathBkp+"\"+$InstSrvOrig.Replace("\","_")+"_"+$BdOrig+"_"+$DataAtual.DayOfYear.ToString()+$DataAtual.Hour.ToString()+$DataAtual.Minute.ToString()+$DataAtual.Millisecond.ToString()+".bkp"
                            Backup-SqlDataBase $BdOrig -ServerInstance $InstSrvOrig -CompressionOption On -BackupFile $NomeArqOrig -verbose 
                            Write-Host "Realizando Backup do Banco de origem... -----> OK "
                        }
                 }
             
             catch  
                   {
                        Write-Host "Falha ao Realizar o Backup do Banco de Origem" 
                        Break 
                    }
            ## Coloca a variável como ok, visto que        
      

                   

    #Faz o backup da base de destino
    Try 
        {
            Write-Host "Realizando Backup do Banco de Destino..."
            $NomeArqDest    =  $PathBkp+"\"+$InstSrvDes.Replace("\","_")+"_"+$BdDest+"_"+$DataAtual.DayOfYear.ToString()+$DataAtual.Hour.ToString()+$DataAtual.Minute.ToString()+$DataAtual.Millisecond.ToString()+".bkp"
            Backup-SqlDataBase $BdDest -ServerInstance $InstSrvDes -CompressionOption On -BackupFile $NomeArqDest -verbose 
            Write-Host "Realizando Backup do Banco de Destino... -----> OK "
        } 
            
    Catch 
        {   Write-Host "Falha ao Realizar o Backup do Banco de Destino" 
            Break 
        }

            #Bloco para deletar e restaurar a base destino    
 

                    #Deleta a base de dados de destino
                    Try {
                            Write-Host "Deletando o Banco de Destino..."
                            Set-Location SQLSERVER:\SQL\$InstSrvDes\Databases\
                            Invoke-Sqlcmd -ServerInstance $InstSrvDes -Query  "ALTER DATABASE [$BdDest] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE DROP DATABASE [$BdDest]"  -verbose 
                            Write-Host "Deletando o Banco de Destino... -----> OK "
                        } 
                    
                    Catch 
                        {   Write-Host "Falha ao deletar o Banco de Destino" 
                             Break 
                        }



                            Write-Host "Exibindo as informações dos DataFiles (Nome Lógico/Nome Físico) "
                            #Faz o restore da Base de dados no destino
                            #Monta a query que realizará o restore da base de dados
                            $cmd            =  ""
                            $MontaQueryRestore | ForEach-Object{
                                $nomeLogico = $_.Name
                                $nomeFisico = $_.physical_name
                                $cmd = $cmd + ", MOVE '$nomeLogico' to '$nomeFisico'"
                                Write-Host $nomeLogico"/"$nomeFisico}

                            
                        
                        Try 
                            {
                                Write-Host "Restaurando o Banco de Destino..."
                                If ($BkpToRest -eq "2") {$NomeArqOrig = $BkpToRestPath}  
                                $cmd = "RESTORE DATABASE $BdDest FROM DISK ='$NomeArqOrig' WITH FILE = 1, RECOVERY, REPLACE $cmd "
                                invoke-sqlcmd -ServerInstance $InstSrvDes -Query $cmd -QueryTimeOut "300" -verbose 
                                Write-Host "Restaurando o Banco de Destino... -----> OK"
                            } 
                                
                        Catch 
                            {   Write-Host "Falha ao restaurar o Banco de Destino" 
                                Break 
                            }
  
                            #Aplica as permissões do usuário
                            
                         Try {
         
                                   Write-Host "Dropando Usuários..."
                                   Invoke-SqlCmd -ServerInstance $InstSrvDes -Query $DropUser -Verbose
                                   Write-Host "Dropando Usuários... -----> OK"

                                   Write-Host "Criando Usuários..."
                                   Invoke-SqlCmd -ServerInstance $InstSrvDes -Query $PermissionUser -Verbose
                                   Write-Host "Criando Usuários... -----> OK"

                              } 
                                 
                            Catch 
                                 {   
                                    Write-Host "Falha ao dropar/criar usuário(s)" 
                                    Break 
                                  }

$DataAtual      =  Get-Date
Write-Host "Fim do processamento: " $DataAtual