using namespace System.Collections.Generic

$parserModule = Join-Path $PSScriptRoot 'HelperModules\TodoListFileParser.ps1'
. $parserModule

$classes = @('Todo', 'TodoList', 'FileTodoListRepository', 'InMemoryTodoListRepository')
$classes | ForEach-Object { . (Join-Path $PSScriptRoot "Classes\${_}.ps1") }

$repositoryMethodsModule = Join-Path $PSScriptRoot 'HelperModules\RepositoryMethods.ps1'
. $repositoryMethodsModule

### Public functions

$publicFunctionsRoot = Join-Path $PSScriptRoot 'Public'
Get-ChildItem (Join-Path $publicFunctionsRoot '*.ps1') | ForEach-Object { . $_.FullName }

# TODO: Add glob filtering on name

New-Alias -Name stodo -Value Set-Todo
New-Alias -Name rmtodo -Value Remove-Todo
New-Alias -Name ntodo -Value New-Todo
New-Alias -Name sttodo -Value Start-Todo
New-Alias -Name ctodo -Value Complete-Todo
New-Alias -Name retodo -Value Reset-Todo
New-Alias -Name mvtodo -Value Move-Todo

Export-ModuleMember -function (Get-ChildItem -Path "$PSScriptRoot\public\*.ps1").BaseName