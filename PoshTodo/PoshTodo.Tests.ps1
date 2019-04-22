using namespace System.Collections.Generic

$moduleName = $MyInvocation.MyCommand.Name.Split('.')[0]
Import-Module -Force (Join-Path $PSScriptRoot "${moduleName}.psm1")
Import-Module -Force (Join-Path $PSScriptRoot 'TestHelpers.psm1')

$ErrorActionPreference = 'Stop'

# We use InModuleScope here so we can mock out the repository functions
# (see the "Private" section of the module).
InModuleScope PoshTodo {
    function Assert-ListExists($Lists, [string] $Name, [string] $Description)
    {
        $matchingLists = @($Lists | Where-Object Name -eq $Name)
        $matchingLists.Count | Should -BeExactly 1
        $matchingLists[0].Description | Should -BeExactly $Description
    }

    Describe 'TodoList CRUD' {
        Context 'New' {
            BeforeAll {
                Mock AddList { }
            }

            It 'creates a new list if list with provided name doesn''t exist' {
                Mock ListExists { $false }

                # Act
                New-TodoList -Name 'Foo'

                # Assert
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
            }

            It 'creates new lists if no lists exist with provided names' {
                Mock ListExists { $false }

                # Act
                New-TodoList -Name 'Foo','Bar','Baz'

                # Assert
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Bar' } -Times 1 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Baz' } -Times 1 -Exactly -Scope It
            }

            It 'throws if a list with the same name already exists' {
                Mock ListExists { $true }

                # Act/Assert
                { New-TodoList -Name 'Foo' -ErrorAction Stop } | Should -Throw 'List with name Foo already exists'
                Assert-MockCalled AddList -Times 0 -Exactly -Scope It
            }

            It 'creates all lists before a list with an existing name is encountered if ErrorAction = Stop' {
                Mock ListExists -ParameterFilter { $Name -eq 'Bar' } { $true }
                Mock ListExists -ParameterFilter { $Name -ne 'Bar' } { $false }

                # Act/Assert
                { New-TodoList -Name 'Foo','Bar','Baz' -ErrorAction Stop } | Should -Throw 'List with name Bar already exists'
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Bar' } -Times 0 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Baz' } -Times 0 -Exactly -Scope It
            }

            It 'creates all lists except those with an existing name if ErrorAction = SilentlyContinue' {
                Mock ListExists -ParameterFilter { $Name -eq 'Bar' } { $true }
                Mock ListExists -ParameterFilter { $Name -ne 'Bar' } { $false }

                # Act/Assert
                { New-TodoList -Name 'Foo','Bar','Baz' -ErrorAction SilentlyContinue } | Should -Not -Throw
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Bar' } -Times 0 -Exactly -Scope It
                Assert-MockCalled AddList -ParameterFilter { $List.Name -eq 'Baz' } -Times 1 -Exactly -Scope It
            }
        }

        Context 'Get' {
            BeforeAll {
                Mock GetLists { @(
                    [TodoList]::new('Default', ''),
                    [TodoList]::new('Foo', 'Bar'),
                    [TodoList]::new('Baz', 'Blorg')
                ) }
            }

            It 'returns all lists with no arguments' {
                # Act
                $retval = @(Get-TodoList)

                # Assert
                $retval.Count | Should -BeExactly 3
                Assert-ListExists $retval 'Default' ''
                Assert-ListExists $retval 'Foo' 'Bar'
                Assert-ListExists $retval 'Baz' 'Blorg'
            }

            It 'returns one list with one name' {
                # Act
                $retval = @(Get-TodoList -Name 'Foo')

                # Assert
                $retval.Count | Should -BeExactly 1
                Assert-ListExists $retval 'Foo' 'Bar'
            }

            It 'returns two lists with two names' {
                # Act
                $retval = @(Get-TodoList -Name 'Foo','Baz')

                # Assert
                $retval.Count | Should -BeExactly 2
                Assert-ListExists $retval 'Foo' 'Bar'
                Assert-ListExists $retval 'Baz' 'Blorg'
            }

            It 'throws with provided name not existing' {
                { Get-TodoList -Name 'Blech' } | Should -Throw 'Could not find list with name: Blech'
            }

            It 'throws with one out of two provided names not existing' {
                { Get-TodoList -Name 'Foo','Block' } | Should -Throw 'Could not find list with name: Block'
            }

            It 'throws correct message with multiple names not existing' {
                { Get-TodoList -Name 'Foo','Block','Baz','Blech' } | Should -Throw 'Could not find lists with names: Block Blech'
            }
        }

        Context 'Set' {
            BeforeEach {
                Mock UpdateList { }
            }

            It 'sets the description of one list by name' {
                Mock GetLists { [TodoList]::new('Foo', '') }

                # Act
                Set-TodoList -Name 'Foo' -Description 'Test'

                # Assert
                Assert-MockCalled UpdateList -Times 1 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and $List.Description -eq 'Test' } -Times 1 -Exactly -Scope It
            }

            It 'sets the description of multiple lists by name' {
                Mock GetLists { [TodoList]::new('Foo', ''), [TodoList]::new('Bar', '') }

                # Act
                Set-TodoList -Name 'Foo','Bar' -Description 'Test'

                # Assert
                Assert-MockCalled UpdateList -Times 2 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and $List.Description -eq 'Test' } -Times 1 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Bar' -and $List.Description -eq 'Test' } -Times 1 -Exactly -Scope It
            }

            It 'sets the description of one list by pipeline' {
                $list = [TodoList]::new('Foo', '')
                Mock GetLists { @($list) }

                # Act
                $list.Description = 'Test'
                $list | Set-TodoList

                # Assert
                Assert-MockCalled UpdateList -Times 1 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and $List.Description -eq 'Test' } -Times 1 -Exactly -Scope It
            }

            It 'sets the description of multiple lists by pipeline' {
                $list1 = [TodoList]::new('Foo', '')
                $list2 = [TodoList]::new('Bar', '')
                Mock GetLists { $list1, $list2 }

                # Act
                $list1.Description = 'Test1'
                $list2.Description = 'Test2'
                $list1, $list2 | Set-TodoList

                # Assert
                Assert-MockCalled UpdateList -Times 2 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and $List.Description -eq 'Test1' } -Times 1 -Exactly -Scope It
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Bar' -and $List.Description -eq 'Test2' } -Times 1 -Exactly -Scope It
            }

            It 'returns updated new lists with -PassThru' {
                $list1 = [TodoList]::new('Foo', 'Baz')
                $list2 = [TodoList]::new('Bar', 'Bat')
                Mock GetLists { $list1, $list2 }

                # Act
                $list1.Description = 'Test1'
                $list2.Description = 'Test2'
                $retval = @($list1, $list2 | Set-TodoList -PassThru)

                # Assert
                $retval.Length | Should -BeExactly 2
                Assert-ListExists $retval 'Foo' 'Test1'
                Assert-ListExists $retval 'Bar' 'Test2'
            }

            It 'modifies existing object references' {
                $list1 = [TodoList]::new('Foo', 'Baz')
                $list2 = [TodoList]::new('Bar', 'Bat')
                Mock GetLists { $list1, $list2 }

                # Act
                $list1.Description = 'Test1'
                $list2.Description = 'Test2'
                $null = @($list1, $list2 | Set-TodoList -PassThru)

                # Assert
                $list1.Description | Should -BeExactly 'Test1'
                $list2.Description | Should -BeExactly 'Test2'
            }

            # 
            It 'doesnt''t modify Description if it isn''t provided' {
                Mock GetLists { [TodoList]::new('Foo', 'Baz') }

                # Act
                Set-TodoList -Name 'Foo'

                # Assert
                Assert-MockCalled UpdateList { $List.Description -eq 'Baz' } -Times 1 -Exactly -Scope It
            }

            It 'sets Description to empty string if the empty string provided' {
                Mock GetLists { [TodoList]::new('Foo', 'Baz') }

                # Act
                Set-TodoList -Name 'Foo' -Description ''

                # Assert
                Assert-MockCalled UpdateList { $List.Description -eq '' } -Times 1 -Exactly -Scope It
            }

            It 'sets Description to empty string if $null is provided' {
                Mock GetLists { [TodoList]::new('Foo', 'Baz') }

                # Act
                Set-TodoList -Name 'Foo' -Description $null

                # Assert
                Assert-MockCalled UpdateList { $List.Description -eq '' } -Times 1 -Exactly -Scope It
            }
        }

        Context 'Remove' {
            BeforeAll {
                Mock RemoveList { }
                Mock GetLists { @(
                    [TodoList]::new('Foo', ''),
                    [TodoList]::new('Bar', 'Bat'),
                    [TodoList]::new('Baz', 'Blorg')
                ) }
                Mock ListExists { $Name -in @('Foo', 'Bar', 'Baz') }
            }

            It 'removes an existing list by name' {
                # Act
                Remove-TodoList -Name 'Foo'

                # Assert
                Assert-MockCalled RemoveList -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
            }

            It 'removes multiple existing lists by name' {
                # Act
                Remove-TodoList -Name 'Foo', 'Baz'

                # Assert
                Assert-MockCalled RemoveList -Times 2 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Baz' } -Times 1 -Exactly -Scope It
            }

            It 'does not throw if list with given name does not exist' {
                # Act/Assert
                { Remove-TodoList -Name 'Blork' } | Should -Not -Throw
                Assert-MockCalled RemoveList -Times 0 -Exactly -Scope It
            }

            It 'removes all existing lists by name and skips nonexistent lists' {
                # Act
                Remove-TodoList -Name 'Foo','Bar','Blork','Baz','Blag'

                # Assert
                Assert-MockCalled RemoveList -Times 3 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Bar' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Blork' } -Times 0 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Baz' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Blag' } -Times 0 -Exactly -Scope It
            }

            It 'removes an existing list by pipeline' {
                $list = [TodoList]::new('Foo', '')
                Mock GetLists { @($list) }

                # Act
                $list | Remove-TodoList

                # Assert
                Assert-MockCalled RemoveList -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
            }

            It 'removes multiple existing lists by pipeline' {
                $list1 = [TodoList]::new('Foo', '')
                $list2 = [TodoList]::new('Bar', '')
                $list3 = [TodoList]::new('Baz', '')
                Mock GetLists { @($list1, $list2, $list3) }

                # Act
                $list1, $list2 | Remove-TodoList

                # Assert
                Assert-MockCalled RemoveList -Times 2 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Bar' } -Times 1 -Exactly -Scope It
            }

            # NOTE: This may occur if a user has a reference to a TodoList object
            # then called Remove-TodoList twice with the same object.
            It 'does not throw if list from pipeline does not exist' {
                $list = [TodoList]::new('Blog', '')

                # Act
                { $list | Remove-TodoList } | Should -Not -Throw

                # Assert
                Assert-MockCalled RemoveList -Times 0 -Exactly -Scope It
            }

            It 'removes all existing lists by pipeline and skips nonexistent lists' {
                $list1 = [TodoList]::new('Foo', '')
                $list2 = [TodoList]::new('Bar', '')
                $list3 = [TodoList]::new('Blork', '')
                $list4 = [TodoList]::new('Baz', '')
                $list5 = [TodoList]::new('Blag', '')
                Mock GetLists { @($list1, $list2, $list4) }

                # Act
                $list1, $list2, $list3, $list4, $list5 | Remove-TodoList

                # Assert
                Assert-MockCalled RemoveList -Times 3 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Foo' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Bar' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Blork' } -Times 0 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Baz' } -Times 1 -Exactly -Scope It
                Assert-MockCalled RemoveList -ParameterFilter { $List.Name -eq 'Blag' } -Times 0 -Exactly -Scope It
            }
        }
    }

    function Test-ListContainsTodo([TodoList] $List, [string] $Description, [string[]] $Tag)
    {
        Test-ContainsTodo $List.Items $Description $Tag
    }

    function Test-ContainsTodo([IEnumerable[Todo]] $Todos, [string] $Description, [string[]] $Tag)
    {
        $null -ne ($Todos | Where-Object { $_.Description -eq $Description } | Where-Object { [System.Linq.Enumerable]::SequenceEqual($_.Tags, $Tag) })
    }

    function Test-ContainsTodoAtIndex([TodoList] $List, [string] $Description, [int] $Index)
    {
        $List.Items.Count -gt $Index -and $List.Items[$Index].Description -eq $Description
    }

    Describe 'Todo CRUD' {
        Context 'New' {
            BeforeAll {
                Mock UpdateList { }
            }

            It 'adds a new todo to the given existing list by name' {
                Mock GetLists { @([TodoList]::new('Foo', '')) }
                Mock ListExists { $Name -eq 'Foo' }

                # Act
                New-Todo -ListName 'Foo' -Description 'Foo the bar' -Tag 'baz','bat'

                # Assert
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and (Test-ListContainsTodo $List 'Foo the bar' @('baz','bat')) } -Times 1 -Exactly -Scope It
            }

            It 'adds a new todo to the given existing list by pipeline' {
                Mock GetLists { @([TodoList]::new('Foo', '')) }
                Mock ListExists { $Name -eq 'Foo' }

                # Act
                $list = [TodoList]::new('Foo', '')
                $list | New-Todo -Description 'Foo the bar' -Tag 'baz','bat'

                # Assert
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Foo' -and (Test-ListContainsTodo $List 'Foo the bar' @('baz','bat')) } -Times 1 -Exactly -Scope It
            }

            It 'adds a new todo to the Default list by default' {
                Mock GetLists { @([TodoList]::new('Default', '')) }
                Mock ListExists { $Name -eq 'Default' }

                # Act
                New-Todo -Description 'Foo the bar' -Tag 'borp','bap'

                # Assert
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Default' -and (Test-ListContainsTodo $List 'Foo the bar' @('borp','bap')) } -Times 1 -Exactly -Scope It
            }

            It 'adds the todo at the correct number in the list using Number' {
                Mock GetLists { @(
                    $list = [TodoList]::new('Default', '')
                    $list.AppendItem([Todo]::new('Test1', @()))
                    $list.AppendItem([Todo]::new('Test2', @()))
                    $list
                ) }
                Mock ListExists { $Name -eq 'Default' }

                # Act
                New-Todo -Description 'Foo the bar' -Number 2

                # Assert
                Assert-MockCalled UpdateList -ParameterFilter { $List.Name -eq 'Default' -and (Test-ContainsTodoAtIndex $List 'Foo the bar' 1) } -Times 1 -Exactly -Scope It
            }

            It 'returns the updated item using -PassThru' {
                Mock GetLists { @([TodoList]::new('Default', '')) }
                Mock ListExists { $Name -eq 'Default' }

                # Act
                $item = New-Todo -Description 'Foo the bar' -Tag 'beep','boop' -PassThru

                # Assert
                $item.Description | Should -BeExactly 'Foo the bar'
                [System.Linq.Enumerable]::SequenceEqual($item.Tags, [string[]] @('beep','boop')) | Should -BeTrue
            }

            It 'doesn''t throw if a todo with the same description exists' {
                Mock GetLists { @(
                    $list = [TodoList]::new('Default', '')
                    $list.AppendItem([Todo]::new('Foo the bar', @('bat')))
                    $list
                ) }
                Mock ListExists { $Name -eq 'Default' }
                Mock Write-Error { }

                # Act/Assert
                { New-Todo -Description 'Foo the bar' -Tag 'bat' } | Should -Not -Throw
                Assert-MockCalled Write-Error -Times 0 -Exactly -Scope It
            }

            It 'throws if the given list name doesn''t exist' {
                Mock GetLists { @([TodoList]::new('Default', '')) }
                Mock ListExists { $Name -eq 'Default' }

                # Act/Assert
                { New-Todo -ListName 'Foo' -Description 'Foo the bar' } | Should -Throw 'Could not find list with name: Foo'
            }

            It 'writes a warning and doesn''t throw if the given list object doesn''t exist in the repository' {
                Mock GetLists { @([TodoList]::new('Default', '')) }
                Mock ListExists { $Name -eq 'Default' }
                Mock Write-Warning { }

                # Act/Assert
                $list = [TodoList]::new('Foo', '')
                { $list | New-Todo -Description 'Foo the bar' } | Should -Not -Throw
                Assert-MockCalled Write-Warning { $Message -eq 'List with name ''Foo'' not found in todo list repository; changes will not be persisted' } -Times 1 -Exactly -Scope It
            }
        }

        Context 'Get' {
            BeforeEach {
                Mock GetLists {
                    $list1 = [TodoList]::new('Default', '')
                    $list1.AppendItem([Todo]::new('Test1', @('Foo')))
                    $list1.AppendItem([Todo]::new('Test2', @('Bar')))
                    $list1.AppendItem([Todo]::new('Test3', @('Baz','Foo')))

                    $list2 = [TodoList]::new('Floo', 'Boop the bar')
                    $list2.AppendItem([Todo]::new('Test4', @()))
                    $list2.AppendItem([Todo]::new('Test5', @('Ban')))
                    $list2.AppendItem([Todo]::new('Test6', @('Ban','Baz')))

                    $list1,$list2
                }
                Mock ListExists { $Name -in @('Default','Floo') }
            }

            It 'returns all todos from the default list with no arguments' {
                # Act
                [List[Todo]] $items = Get-Todo

                # Assert
                $items.Count | Should -BeExactly 3
                Test-ContainsTodo $items 'Test1' @('Foo') | Should -BeTrue
                Test-ContainsTodo $items 'Test2' @('Bar') | Should -BeTrue
                Test-ContainsTodo $items 'Test3' @('Baz','Foo') | Should -BeTrue
            }

            It 'returns a specific todo by number' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Number 2

                # Assert
                $items.Count | Should -BeExactly 1
                Test-ContainsTodo $items 'Test2' @('Bar') | Should -BeTrue
            }

            It 'returns all todos matching one tag' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Tag 'Foo'

                # Assert
                $items.Count | Should -BeExactly 2
                Test-ContainsTodo $items 'Test1' @('Foo') | Should -BeTrue
                Test-ContainsTodo $items 'Test3' @('Baz','Foo') | Should -BeTrue
            }

            It 'returns all todos matching at least one tag' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Tag 'Bloch','Bar','Fleck'

                # Assert
                $items.Count | Should -BeExactly 1
                Test-ContainsTodo $items 'Test2' @('Bar') | Should -BeTrue
            }

            It 'returns no todos when no tags match' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Tag 'Bloch','Fleck'

                # Assert
                $items.Count | Should -BeExactly 0
            }

            It 'returns todo by number if it matches at least one tag' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Number 2 -Tag 'Bloch','Bar','Fleck'

                # Assert
                $items.Count | Should -BeExactly 1
                Test-ContainsTodo $items 'Test2' @('Bar') | Should -BeTrue
            }

            It 'returns no todos by number if it matches no tags' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Default' -Number 2 -Tag 'Bloch','Fleck'

                # Assert
                $items.Count | Should -BeExactly 0
            }

            It 'returns all items in a list by pipeline' {
                $list = [TodoList]::new('Default', '')
                $list.AppendItem([Todo]::new('Test1', @('Foo')))
                $list.AppendItem([Todo]::new('Test2', @('Bar')))
                $list.AppendItem([Todo]::new('Test3', @('Baz','Foo')))
                Mock GetLists { $list }
                Mock ListExists { $Name -eq 'Default' }

                # Act
                [List[Todo]] $items = $list | Get-Todo

                # Assert
                $items.Count | Should -BeExactly 3
                Test-ContainsTodo $items 'Test1' @('Foo') | Should -BeTrue
                Test-ContainsTodo $items 'Test2' @('Bar') | Should -BeTrue
                Test-ContainsTodo $items 'Test3' @('Baz','Foo') | Should -BeTrue
            }

            It 'returns all items in a list by list name' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Floo'

                # Assert
                $items.Count | Should -BeExactly 3
                Test-ContainsTodo $items 'Test4' @() | Should -BeTrue
                Test-ContainsTodo $items 'Test5' @('Ban') | Should -BeTrue
                Test-ContainsTodo $items 'Test6' @('Ban','Baz') | Should -BeTrue
            }

            It 'returns no item and does not throw when the number is out of range' {
                # Act
                [List[Todo]] $items = Get-Todo -ListName 'Floo' -Number 6 -ErrorAction Stop

                # Assert
                $items.Count | Should -BeExactly 0
            }
        }

        Context 'Set' {
            BeforeEach {
                Mock UpdateList { }
            }

            It 'updates item in the default list by default' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list2 = [TodoList]::new('Default', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list2.AppendItem($item)
                Mock GetLists { $list1,$list2 }
                Mock ListExists { $true }

                # Act
                Set-Todo -Item $item -Description 'Blech' -Tag @('Bat')

                # Assert
                $list2.Items[0].Description | Should -BeExactly 'Blech'
                $tags = @($list2.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'updates by list name' {
                # Arrange
                $list1 = [TodoList]::new('Default', '')
                $list2 = [TodoList]::new('Floog', '')
                $list3 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list2.AppendItem($item)
                Mock GetLists { $list1,$list2,$list3 }
                Mock ListExists { $true }

                # Act
                Set-Todo -ListName 'Floog' -Number 1 -Description 'Blech' -Tag @('Bat')

                # Assert
                $list2.Items[0].Description | Should -BeExactly 'Blech'
                $tags = @($list2.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'updates by list object from pipeline' {
                # Arrange
                $list1 = [TodoList]::new('Default', '')
                $list2 = [TodoList]::new('Floog', '')
                $list3 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list2.AppendItem($item)
                Mock GetLists { $list1,$list2,$list3 }
                Mock ListExists { $true }

                # Act
                $list2 | Set-Todo -Number 1 -Description 'Blech' -Tag @('Bat')

                # Assert
                $list2.Items[0].Description | Should -BeExactly 'Blech'
                $tags = @($list2.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'updates by todo item from pipeline' {
                # Arrange
                $list1 = [TodoList]::new('Default', '')
                $list2 = [TodoList]::new('Floog', '')
                $list3 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list3.AppendItem($item)
                Mock GetLists { $list1,$list2,$list3 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo -Description 'Blech' -Tag @('Bat')

                # Assert
                $list3.Items[0].Description | Should -BeExactly 'Blech'
                $tags = @($list3.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'does not invoke update if item is orphaned' {
                 # Arrange
                $list1 = [TodoList]::new('Test', '')
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                Mock Write-Warning { }

                # Act
                $item = [Todo]::new('Foo bar', @('Baz'))
                Set-Todo -Item $item -Description 'Blech' -Tag @('Bat')

                # Assert
                $item.Description | Should -BeExactly 'Blech'
                $tags = @($item.Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
                Assert-MockCalled Write-Warning -Exactly -Times 1 -Scope It
            }

            It 'invokes update on item if neither tag nor description is provided' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo

                # Assert
                $list1.Items[0].Description | Should -BeExactly 'Foo bar'
                $tags = @($list1.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Baz'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'only updates tag if it is provided' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo -Tag @('Bat')

                # Assert
                $list1.Items[0].Description | Should -BeExactly 'Foo bar'
                $tags = @($list1.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Bat'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'only updates description if it is provided' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo -Description 'Blech'

                # Assert
                $list1.Items[0].Description | Should -BeExactly 'Blech'
                $tags = @($list1.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Baz'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'updates description to empty string if it is provided' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo -Description ''

                # Assert
                $list1.Items[0].Description | Should -BeExactly ''
                $tags = @($list1.Items[0].Tags)
                $tags.Count | Should -BeExactly 1
                $tags[0] | Should -BeExactly 'Baz'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'updates tags to empty if it is provided' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Set-Todo -Tag @()

                # Assert
                $list1.Items[0].Description | Should -BeExactly 'Foo bar'
                $tags = @($list1.Items[0].Tags)
                $tags.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }
        }

        Context 'Remove' {
            BeforeEach {
                Mock UpdateList { }
            }

            It 'removes the todo from the default list by default' {
                # Arrange
                $list1 = [TodoList]::new('Default', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                Remove-Todo -Number 1

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'removes the todo by list name & number' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                Remove-Todo -ListName 'Test' -Number 1

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'removes the todo by list property & number' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                Remove-Todo -List $list1 -Number 1

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'removes the todo by list pipeline & number' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $list1 | Remove-Todo -Number 1

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'removes the todo by item property' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                Remove-Todo -Item $item

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'removes the todo by item pipeline' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo bar', @('Baz'))
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }

                # Act
                $item | Remove-Todo

                # Assert
                $list1.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'throws if list name does not exist' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $Name -eq 'Test' }

                # Act
                { Remove-Todo -ListName 'Boo' -Number 1 } | Should -Throw

                # Assert
                $list1.Items.Count | Should -BeExactly 1
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }

            It 'updates list object but not backing list if list object does not exist' {
                # Arrange
                $realList = [TodoList]::new('Test', '')
                $realList.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $realList }
                Mock ListExists { $Name -eq 'Test' }
                Mock Write-Warning { }

                # Act
                $fakeList = [TodoList]::new('Test2', '')
                $fakeList.AppendItem([Todo]::new('Bat baz', @()))
                Remove-Todo -List $fakeList -Number 1

                # Assert
                $realList.Items.Count | Should -BeExactly 1
                $fakeList.Items.Count | Should -BeExactly 0
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
                Assert-MockCalled Write-Warning -Times 1 -Scope It
            }

            It 'does nothing if number does not exist' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $Name -eq 'Test' }

                # Act
                Remove-Todo -ListName 'Test' -Number 3

                # Assert
                $list1.Items.Count | Should -BeExactly 1
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }

            It 'does nothing if todo item is not in a list' {
                # Arrange
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo bar', @('Baz')))
                Mock GetLists { $list1 }
                Mock ListExists { $Name -eq 'Test' }

                # Act
                $fakeItem = [Todo]::new('Bar baz', @())
                Remove-Todo -Item $fakeItem

                # Assert
                $list1.Items.Count | Should -BeExactly 1
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }
        }

        Context 'Move' {
            BeforeEach {
                $list1 = [TodoList]::new('Test', '')
                $item1 = [Todo]::new('Foo bar 1', @('Baz'))
                $item2 = [Todo]::new('Foo bar 2', @('Baz'))
                $item3 = [Todo]::new('Foo bar 3', @('Baz'))
                $list1.AppendItem($item1)
                $list1.AppendItem($item2)
                $list1.AppendItem($item3)
                Mock UpdateList { }
                Mock GetLists { $list1 }
                Mock ListExists { $Name -eq 'Test' }
            }

            It 'moves item by list name' {
                # Act
                Move-Todo -ListName 'Test' -Number 1 -ToNumber 3

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'moves item by list object' {
                # Act
                Move-Todo -List $list1 -Number 1 -ToNumber 3

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'moves item by list pipeline' {
                # Act
                $list1 | Move-Todo -Number 1 -ToNumber 3

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'moves item by item property' {
                # Act
                Move-Todo -Item $item1 -ToNumber 3

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'moves item by item pipeline' {
                # Act
                $item1 | Move-Todo -ToNumber 3

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'throws if list name does not exist' {
                # Act
                { Move-Todo -ListName 'Boo' -Number 1 -ToNumber 3 } | Should -Throw

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 1'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 3'
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }

            It 'updates list object but not backing list if list object does not exist' {
                # Arrange
                Mock Write-Warning { }

                # Act
                $fakeList = [TodoList]::new('Test2', '')
                $fakeList.AppendItem([Todo]::new('Bat baz', @()))
                $fakeList.AppendItem([Todo]::new('Bat bam', @()))
                Move-Todo -List $fakeList -Number 1 -ToNumber 2

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 1'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 3'
                $fakeList.GetItem(1) | Assert-ItemMatches -Description 'Bat bam'
                $fakeList.GetItem(2) | Assert-ItemMatches -Description 'Bat baz'
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
                Assert-MockCalled Write-Warning -Times 1 -Scope It
            }

            It 'throws if number does not exist' {
                # Act/Assert
                { Move-Todo -ListName 'Test' -Number 4 -ToNumber 1 } | Should -Throw
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }

            It 'throws if item does not exist' {
                # Arrange
                $item4 = [Todo]::new('Foo bar 4', @('Baz'))

                # Act/Assert
                { Move-Todo -Item $item4 -ToNumber 2 } | Should -Throw
                Assert-MockCalled UpdateList -Exactly -Times 0 -Scope It
            }

            It 'appends item to end if target number is too large' {
                # Act
                $item1 | Move-Todo -ToNumber 10

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 1'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'prepends item to start if target number is less than one' {
                # Act
                $item3 | Move-Todo -ToNumber -1

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 1'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 2'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'does nothing if item number and target number are the same' {
                # Act
                $item2 | Move-Todo -ToNumber 2

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 1'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 3'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'inserts item at the correct position' {
                # Arrange
                $item4 = [Todo]::new('Foo bar 4', @('Baz'))
                $item5 = [Todo]::new('Foo bar 5', @('Baz'))
                $item6 = [Todo]::new('Foo bar 6', @('Baz'))
                $list1.AppendItem($item4)
                $list1.AppendItem($item5)
                $list1.AppendItem($item6)

                # Act
                $item2 | Move-Todo -ToNumber 5

                # Assert
                $list1.GetItem(1) | Assert-ItemMatches -Description 'Foo bar 1'
                $list1.GetItem(2) | Assert-ItemMatches -Description 'Foo bar 3'
                $list1.GetItem(3) | Assert-ItemMatches -Description 'Foo bar 4'
                $list1.GetItem(4) | Assert-ItemMatches -Description 'Foo bar 5'
                $list1.GetItem(5) | Assert-ItemMatches -Description 'Foo bar 2'
                $list1.GetItem(6) | Assert-ItemMatches -Description 'Foo bar 6'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }
        }
    }

    Describe 'Todo Methods' {
        Context 'IsEqualTo' {
            function New-TodoItem([int] $Number, [string] $Description, [string] $Status, [string[]] $Tags)
            {
                $item = [Todo]::new($Description, $Tags)
                $item.Number = $Number
                $item.Status = $Status
                return $item
            }

            It 'is false when only description differs' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Bat' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when only status differs' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Foo' 'IN PROGRESS' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when only number differs' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 4 'Foo' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is the subset of the other' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Foo' 'TODO' @('Bar','Bat')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is the superset of the other' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar','Bat')
                $item2 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is empty and the other is non-empty' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @()
                $item2 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is null and the other is non-empty' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' $null
                $item2 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is non-empty and the other is empty' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Foo' 'TODO' @()
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is false when one tag set is non-empty and the other is null' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Foo' 'TODO' $null
                $item1.IsEqualTo($item2) | Should -BeFalse
            }

            It 'is true when both non-empty tag sets are equal' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item2 = New-TodoItem 3 'Foo' 'TODO' @('Bar')
                $item1.IsEqualTo($item2) | Should -BeTrue
            }

            It 'is true when one tag set is empty and one is null' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @()
                $item2 = New-TodoItem 3 'Foo' 'TODO' $null
                $item1.IsEqualTo($item2) | Should -BeTrue
            }

            It 'is true when one tag set is null and one is empty' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' $null
                $item2 = New-TodoItem 3 'Foo' 'TODO' @()
                $item1.IsEqualTo($item2) | Should -BeTrue
            }

            It 'is true when both tag sets are null' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' $null
                $item2 = New-TodoItem 3 'Foo' 'TODO' $null
                $item1.IsEqualTo($item2) | Should -BeTrue
            }

            It 'is true when both tag sets are empty' {
                $item1 = New-TodoItem 3 'Foo' 'TODO' @()
                $item2 = New-TodoItem 3 'Foo' 'TODO' @()
                $item1.IsEqualTo($item2) | Should -BeTrue
            }
        }
    }

    Describe 'Todo Tasks' {
        BeforeEach {
            Mock UpdateList { }
        }

        Context 'Start' {
            BeforeEach {
                Mock UpdateList { }
            }

            It 'starts a todo from the default list by default' {
                $list1 = [TodoList]::new('Default', '')
                $list1.AppendItem([Todo]::new('Foo the bar', @()))
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts a todo by item property' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -Item $item

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts a todo by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item | Start-Todo

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts multiple todos by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item1 = [Todo]::new('Foo the bar 1', @())
                $item2 = [Todo]::new('Foo the bar 2', @())
                $item3 = [Todo]::new('Foo the bar 3', @())
                $list1.AppendItem($item1)
                $list1.AppendItem($item2)
                $list1.AppendItem($item3)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item1,$item3 | Start-Todo

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                $list1.Items[1].Status | Should -BeExactly 'TODO'
                $list1.Items[2].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 2 -Scope It
            }

            It 'starts a todo by list name + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -ListName 'Test' -Number 1

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts a todo by list object property + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -List $list1 -Number 1

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts a todo by list object pipeline + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $list1 | Start-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'starts a completed todo' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -Item $item

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'does not affect an in-progress todo' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'IN PROGRESS'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Start-Todo -Item $item

                $list1.Items[0].Status | Should -BeExactly 'IN PROGRESS'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }
        }

        Context 'Complete' {
            It 'completes a todo from the default list by default' {
                $list1 = [TodoList]::new('Default', '')
                $list1.AppendItem([Todo]::new('Foo the bar', @()))
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Complete-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'completes a todo by item property' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Complete-Todo -Item $item

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'completes a todo by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item | Complete-Todo

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'completes multiple todos by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item1 = [Todo]::new('Foo the bar 1', @())
                $item2 = [Todo]::new('Foo the bar 2', @())
                $item3 = [Todo]::new('Foo the bar 3', @())
                $list1.AppendItem($item1)
                $list1.AppendItem($item2)
                $list1.AppendItem($item3)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item1,$item3 | Complete-Todo

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                $list1.Items[1].Status | Should -BeExactly 'TODO'
                $list1.Items[2].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 2 -Scope It
            }

            It 'completes a todo by list name + number' {
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo the bar', @()))
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Complete-Todo -ListName 'Test' -Number 1

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'completes a todo by list object property + number' {
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo the bar', @()))
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Complete-Todo -List $list1 -Number 1

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'completes a todo by list object pipeline + number' {
                $list1 = [TodoList]::new('Test', '')
                $list1.AppendItem([Todo]::new('Foo the bar', @()))
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $list1 | Complete-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'does not affect a completed todo' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($Item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Complete-Todo -List $list1 -Number 1

                $list1.Items[0].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }
        }

        Context 'Reset' {
            It 'resets a todo from the default list by default' {
                $list1 = [TodoList]::new('Default', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Reset-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets a todo by item property' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Reset-Todo -Item $item

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets a todo by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item | Reset-Todo

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets multiple todos by item pipeline' {
                $list1 = [TodoList]::new('Test', '')
                $item1 = [Todo]::new('Foo the bar 1', @())
                $item2 = [Todo]::new('Foo the bar 2', @())
                $item3 = [Todo]::new('Foo the bar 3', @())
                $item1.Status = 'COMPLETE'
                $item2.Status = 'COMPLETE'
                $item3.Status = 'COMPLETE'
                $list1.AppendItem($item1)
                $list1.AppendItem($item2)
                $list1.AppendItem($item3)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item1,$item2 | Reset-Todo

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                $list1.Items[1].Status | Should -BeExactly 'TODO'
                $list1.Items[2].Status | Should -BeExactly 'COMPLETE'
                Assert-MockCalled UpdateList -Exactly -Times 2 -Scope It
            }

            It 'resets a todo by list name + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Reset-Todo -ListName 'Test' -Number 1

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets a todo by list object property + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                Reset-Todo -List $list1 -Number 1

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets a todo by list object pipeline + number' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'COMPLETE'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $list1 | Reset-Todo -Number 1

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'resets an in-progress todo' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'IN PROGRESS'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item | Reset-Todo

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }

            It 'does not affect an unstarted todo' {
                $list1 = [TodoList]::new('Test', '')
                $item = [Todo]::new('Foo the bar', @())
                $item.Status = 'TODO'
                $list1.AppendItem($item)
                Mock GetLists { $list1 }
                Mock ListExists { $true }
                
                # Act
                $item | Reset-Todo

                $list1.Items[0].Status | Should -BeExactly 'TODO'
                Assert-MockCalled UpdateList -Exactly -Times 1 -Scope It
            }
        }
    }

    Describe 'Integration' {
        BeforeEach {
            [InMemoryRepository]::Reset()
        }

        Context 'Get-Todo returns items from New-Todo' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Test1' -Tag 'foo','bar' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Test2' -Tag 'foo','bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Test3' -Tag 'bar','bat' -PassThru

            # Act
            $results = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should return the correct number of todos' {
                $results.Length | Should -BeExactly 3
            }

            It 'should return the Test1 item' {
                $item1 | Assert-TodoInResults -Results $results
            }

            It 'should return the Test2 item' {
                $item2 | Assert-TodoInResults -Results $results
            }

            It 'should return the Test3 item' {
                $item3 | Assert-TodoInResults -Results $results
            }
        }

        Context 'Get-Todo returns items updated from Set-Todo' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Test1' -Tag 'foo','bar' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Test2' -Tag 'foo','bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Test3' -Tag 'bar','bat' -PassThru

            # Act
            $item1 | Set-Todo -Description 'Foobar' -Tag 'bat','baz'
            $results = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should return the correct number of todos' {
                $results.Length | Should -BeExactly 3
            }
            It 'should return the updated description' {
                $item1,$results[0] | Assert-ItemMatches -Description 'Foobar'
            }
            It 'should return the updated tags' {
                $item1,$results[0] | Assert-ItemMatches -Tags 'bat','baz'
            }
            It 'updates item reference' {
                $item1 | Assert-ItemMatches -Description 'Foobar' -Tags 'bat','baz'
            }
        }

        Context 'Get-Todo does not return deleted items' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Test1' -Tag 'foo','bar' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Test2' -Tag 'foo','bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Test3' -Tag 'bar','bat' -PassThru

            # Act
            $item1 | Remove-Todo
            $results = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should return the correct number of todos' {
                $results.Length | Should -BeExactly 2
            }
            It 'should not return the deleted todo' {
                $item1 | Assert-TodoNotInResults -Results $results
            }
        }

        Context 'Set-Todo updates by Number' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Test1' -Tag 'foo','bar' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Test2' -Tag 'foo','bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Test3' -Tag 'bar','bat' -PassThru

            # Act
            $item3.Description = 'Barfoo'
            $item3.Tags = @('blech','bam','boo')
            $item3 | Set-Todo
            $results = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should update the todo with matching Number' {
                $item3,$results[2] | Assert-ItemMatches -Description 'Barfoo' -Tags 'blech','bam','boo'
            }
        }

        Context 'Remove-Todo removes exactly originally matching items if filtering on number' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Foo bar 1' -Tag 'Baz' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Foo bar 2' -Tag 'Bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Foo bar 3' -Tag 'Ban' -PassThru

            # Act
            $before = @(Get-Todo -ListName 'Test')
            $before | Where-Object Number -eq 1 | Remove-Todo
            $after = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should return the correct number of todos' {
                $after.Length | Should -BeExactly 2
            }
            It 'should not contain the removed todo' {
                $item1 | Assert-TodoNotInResults -Results $after
                $item2 | Assert-TodoInResults -Results $after
                $item3 | Assert-TodoInResults -Results $after
            }
            It 'should leave the list reference unaffected' {
                $before.Length | Should -BeExactly 3
                $item1 | Assert-TodoInResults -Results $before
            }
        }

        Context 'Move-Todo operates on original list when filtering by number' {
            # Arrange
            New-TodoList -Name 'Test'
            1..6 | ForEach-Object { New-Todo -ListName 'Test' -Description "Foo bar $_" -Tag 'Baz' }

            # Act
            $before = @(Get-Todo -ListName 'Test')
            $before | Sort-Object Number -Descending | Where-Object Number -le 3 | Move-Todo -ToNumber 10
            $after = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should return the correct number of todos' {
                $after.Length | Should -BeExactly 6
            }
            It 'should return the todos in the correct order' {
                $after[0].Description | Should -BeExactly 'Foo bar 4'
                $after[1].Description | Should -BeExactly 'Foo bar 5'
                $after[2].Description | Should -BeExactly 'Foo bar 6'
                $after[3].Description | Should -BeExactly 'Foo bar 3'
                $after[4].Description | Should -BeExactly 'Foo bar 2'
                $after[5].Description | Should -BeExactly 'Foo bar 1'
            }
        }

        Context 'Task-related functions correctly update via pipeline' {
            # Arrange
            New-TodoList -Name 'Test'
            $item1 = New-Todo -ListName 'Test' -Description 'Foo bar 1' -Tag 'Baz' -PassThru
            $item2 = New-Todo -ListName 'Test' -Description 'Foo bar 2' -Tag 'Bat' -PassThru
            $item3 = New-Todo -ListName 'Test' -Description 'Foo bar 3' -Tag 'Ban' -PassThru

            # Act
            $item1 | Start-Todo
            $item2 | Complete-Todo
            $item3 | Reset-Todo
            $results = @(Get-Todo -ListName 'Test')

            # Assert
            It 'should have started the first todo' {
                $item1 | Assert-ItemMatches -Status 'IN PROGRESS'
                $results[0] | Assert-ItemMatches -Status 'IN PROGRESS'
            }
            It 'should have completed the second todo' {
                $item2 | Assert-ItemMatches -Status 'COMPLETE'
                $results[1] | Assert-ItemMatches -Status 'COMPLETE'
            }
            It 'should have reset the third todo' {
                $item3 | Assert-ItemMatches -Status 'TODO'
                $results[2] | Assert-ItemMatches -Status 'TODO'
            }
        }
    }
}