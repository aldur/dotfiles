call ale#linter#Define('sh', {
            \   'name': 'dotenv-linter',
            \   'executable': 'dotenv-linter',
            \   'command': 'dotenv-linter %t',
            \   'callback': 'aldur#ale#handle_dotenv_linter_format',
            \})
