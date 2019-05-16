import subprocess


def yes_no(answer : str):
  yes = set(['yes','y', 'ye', ''])
  no = set(['no','n'])
  while True:
    choice = input(answer + ' y/n?').lower()
    if choice in yes:
      return True
    elif choice in no:
      return False
    else:
      print("Please respond with Y/N")

# TODO: provide util to run the bash script, error message and bash -x
# in case when the returning result is wrong.

def invoke_cmd(cmd : str):
  invoke = subprocess.Popen(
    cmd.split(' ')
  )
  print('Running command: %s ' % cmd)
  invoke.wait()
  